#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

"Provides selected configuration possibilites via REDFISH REST management api."

import json
import sys
import time
import warnings
import argparse
import requests  # pylint: disable=import-error


warnings.filterwarnings("ignore")


def join_url(*pieces):
    "Single url join splited url."
    return "/".join(s.strip("/") for s in pieces)


class RedfishAPI:
    "Redfish api rest wrapper."

    # How many seconds to wait for the server to send data before giving up
    HTTP_RESPONSE_TIMEOUT = 10

    def __init__(self, base_url, username, password, proxy=None, verbose=False):
        self.base_url = "https://" + join_url(base_url, "/redfish/v1")
        self.username = username
        self.password = password
        self.proxy = proxy
        self.verbose = verbose
        self._system_id = None

    def _request(self, method: str, endpoint: str, check=True, **kwargs):
        """Generic http request.

        Note:
            First argument method is case sensitive it has to be exact method
            name as in requests library.
        Args:
            method: String name of http method available in
                requests library. Possible values: get, post, put, patch, delete.
            endpoint: API Path to be appended to url/redfish/v1
            check: Whether check response for accepted http status
                code (2xx/3xx) and exit 1 if bad status code occurs.
            kwargs: Extra named parameters to pass for requests
                http call.
        Returns:
            requests.Response: The Response object, which contains a server's response to an HTTP request.
        """
        def print_extended_info(response):
            try:
                print(f"Extended Info Message: {json.dumps(response.json(), indent=2)}")
            except Exception as e:
                print(f"\n- FAIL, Can't decode extended info message. Exception: {e}")

        def check_response(response):
            try:
                response.raise_for_status()
            except requests.HTTPError as e:
                print(f"\n- FAIL, Request returned inccorect response code: {e}")
                print_extended_info(response)
                sys.exit(1)

        if "data" in kwargs:
            kwargs["data"] = json.dumps(kwargs["data"])

        # gets http method attribute by name and calls it
        response = getattr(requests, method)(join_url(self.base_url, endpoint),
                                             verify=False,  # nosec
                                             auth=(self.username, self.password),
                                             proxies=self.proxy,
                                             timeout=self.HTTP_RESPONSE_TIMEOUT,
                                             **kwargs)
        if check:
            check_response(response)

        if self.verbose:
            print_extended_info(response)
        return response

    @property
    def system_id(self) -> str:
        """Returns id of first system managed by interface.

        Note:
            Assumes there will be only single member.
            Redfish api host system id can vary depending on platform.
            Supermicro system_id is usually '1' and dell 'System.Embedded.1'.
        """
        if not self._system_id:
            response = self._request("get", "/Systems/")
            self._system_id = str(response.json()["Members"][0]["@odata.id"]).replace("/redfish/v1/Systems/", "")
        return self._system_id

    @property
    def is_supermicro(self) -> bool:
        return self.system_id == "1"

    @property
    def is_dell(self) -> bool:
        return self.system_id == "System.Embedded.1"

    def patch_secure_boot(self, payload_data):
        """Sends PATCH rest request to system /SecureBoot endpoint.

        Note:
            This call will automatically create config job that will update
            set values opposite to calls to /Bios/Settings (for dell).
        Args:
            payload_data dict: Dictionary data to be send as json.

        Returns:
            requests.Response object containing response to patch rest call
        """
        headers = {"content-type": "application/json"}
        return self._request("patch",
                             f"/Systems/{self.system_id}/SecureBoot",
                             headers=headers,
                             data=payload_data)

    def patch_bios_settings(self, payload_data):
        """Sends PATCH rest request to system /Bios endpoint.

        Args:
            payload_data dict: Dictionary data to be send as json.

        Returns:
            requests.Response object containing response to patch rest call
        """
        headers = {"content-type": "application/json"}
        return self._request("patch",
                             f"/Systems/{self.system_id}/Bios/Settings",
                             headers=headers,
                             data=payload_data)

    def enable_secure_boot(self):
        """Enables secure boot for given system.

        Note:
            Based on system_id different json payload is provided to system.
        """
        # supermicro has different payload
        payload = {"SecureBoot": "Enabled"} if self.is_supermicro else {"SecureBootEnable": True}
        response = self.patch_secure_boot(payload)
        print(f"- PASS, Secure boot command successful, code return is {response.status_code}")

    def disable_secure_boot(self):
        """Disables secure boot for given system.

        Note:
            Based on system_id different json payload is provided to system.
        """
        # supermicro has different payload
        payload = {"SecureBoot": "Disabled"} if self.is_supermicro else {"SecureBootEnable": False}
        response = self.patch_secure_boot(payload)
        print(f"- PASS, Secure boot command successful, code return is {response.status_code}")

    def get_secure_boot_enable_status(self) -> bool:
        """Returns bool value representing state of secure boot.

        Returns:
            True if secure boot is enabled for system otherwise
            False.
        """
        response = self._request("get", f"/Systems/{self.system_id}/SecureBoot")
        data = response.json()
        # supermicro option "SecureBoot" is string while dell store bools in json
        return data["SecureBoot"] == "Enabled" if self.is_supermicro else data["SecureBootEnable"]

    def create_bios_config_job(self) -> requests.Request:
        """Creates bios config job for dell iDRAC.
        For applying changes added to /Bios/Settings endpoint.
        """
        payload = {"TargetSettingsURI": "/redfish/v1/Systems/System.Embedded.1/Bios/Settings"}
        headers = {"content-type": "application/json"}
        return self._request("post",
                             "/Managers/iDRAC.Embedded.1/Jobs",
                             headers=headers,
                             data=payload)

    def enable_tpm(self):
        """Enables trusted platform module support for given system.
        """
        # TODO: Check what is payload/endpoint for supermicro
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")

        payload = {"Attributes": {"TpmSecurity": "On"}}
        response = self.patch_bios_settings(payload)
        print(f"- PASS, Bios patch command successful, code return is {response.status_code}")
        # Changes in dell bios setting reqire creation of config job for them to take effect
        if self.is_dell:
            self.create_bios_config_job()

    def disable_tpm(self):
        """Disables trusted platform module support for given system.
        """
        # TODO: Check what is payload/endpoint for supermicro
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")

        payload = {"Attributes": {"TpmSecurity": "Off"}}
        response = self.patch_bios_settings(payload)
        print(f"- PASS, Bios patch command successful, code return is {response.status_code}")
        # Changes in dell bios setting reqire creation of config job for them to take effect
        if self.is_dell:
            self.create_bios_config_job()

    def get_tpm(self) -> bool:
        """Returns bool value representing status of system trusted platform module support.

        Returns:
            True if trusted platform module support is enabled for system otherwise
            False.
        """
        # TODO: Check what is payload/endpoint for supermicro
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")

        response = self._request("get", f"/Systems/{self.system_id}/Bios")
        data = response.json()
        return data["Attributes"]["TpmSecurity"] == "On"

    def reboot_server(self):
        """Reboots given system.
        """
        response = self._request("get", f"/Systems/{self.system_id}/")
        data = response.json()
        print(f"\n- WARNING, Current server power state is: {data['PowerState']}")
        if data['PowerState'] == "On":
            endpoint = f"/Systems/{self.system_id}/Actions/ComputerSystem.Reset"
            payload = {"ResetType": "GracefulShutdown"}
            headers = {"content-type": "application/json"}
            response = self._request("post",
                                     endpoint,
                                     data=payload,
                                     headers=headers)

            # time to wait until system in Off state in seconds / number of checks (1 check per second)
            wait_limit = 20

            for _ in range(wait_limit):
                response = self._request("get", f"/Systems/{self.system_id}", check=False)
                data = response.json()
                if data["PowerState"] == "Off":
                    print("- PASS, GET command passed to verify server is in OFF state")
                    break
                time.sleep(1)
            else:
                print("\n- FAIL, Command failed to gracefully power OFF server in given interval")
                sys.exit(1)

            payload = {"ResetType": "On"}
            headers = {"content-type": "application/json"}
            response = self._request("post",
                                     endpoint,
                                     data=payload,
                                     headers=headers)

            print(f"- PASS, Command passed to power ON server, code return is {response.status_code}")

        elif data['PowerState'] == "Off":
            endpoint = f"/Systems/{self.system_id}/Actions/ComputerSystem.Reset"
            payload = {"ResetType": "On"}
            headers = {"content-type": "application/json"}
            response = self._request("post",
                                     endpoint,
                                     data=payload,
                                     headers=headers)
            print(f"- PASS, Command passed to power ON server, code return is {response.status_code}")


def parse_args():
    """Parse argument passed in stdin"""
    class CustomFormatter(argparse.ArgumentDefaultsHelpFormatter, argparse.RawDescriptionHelpFormatter):
        "Default parsers except help"
    parser = argparse.ArgumentParser(description="This script utilizes Redfish API to "
                                                 "perform management operations on "
                                                 "iDRAC or SUPERMICRO machine.",
                                                 formatter_class=CustomFormatter,
                                                 epilog="Note: Tool will not perform reboot by default it is user\n"
                                                        "decision if operation performed requires it.\n\n"
                                                        "Examples:\n"
                                                        "> %(prog)s.py sb on -u "
                                                        "calvin -p rootpass --ip 10.22.22.139 -r\n\n"
                                                        "> %(prog)s.py tpm get -u "
                                                        "calvin -p rootpass --ip 10.22.22.139\n\n"
                                                        "> %(prog)s.py tpm off -u "
                                                        "calvin -p rootpass --ip 10.22.22.139")

    parent_parser = argparse.ArgumentParser(add_help=False)
    parent_parser.add_argument("--ip", help="MGMT IP address.", required=True)
    parent_parser.add_argument("-u", "--user", help="MGMT username.", required=True)
    parent_parser.add_argument("-p", "--password", help="MGMT password.", required=True)
    parent_parser.add_argument("--proxy", help="Proxy server for traffic redirection.", required=False)
    parent_parser.add_argument("-r", "--reboot",
                               help="Rebot remote machine after operation performed.",
                               required=False,
                               action="store_true")
    parent_parser.add_argument("-v", "--verbose",
                               help="Extend verbosity.",
                               required=False,
                               action="store_true",
                               default=False)

    switch_parser = argparse.ArgumentParser(add_help=False)
    switch_parser.add_argument("action",
                               choices=["on", "off", "get"],
                               help="Action to be performed with given command.")

    subparsers = parser.add_subparsers(dest="command",
                                       help="Implemented operations",
                                       required=True)
    subparsers.add_parser("sb",
                          help="Secure boot configuration.",
                          parents=[parent_parser, switch_parser])

    subparsers.add_parser("tpm",
                          help="Trusted module platform configuration.",
                          parents=[parent_parser, switch_parser])

    return parser.parse_args()


def main():
    "Main execution function"
    args = parse_args()
    proxy = {}
    if args.proxy:
        proxy["http"] = args.proxy
        proxy["https"] = args.proxy
    rapi = RedfishAPI(args.ip,
                      args.user,
                      args.password,
                      proxy=proxy,
                      verbose=args.verbose)

    print(f"- PASS, Retrieved system id: {rapi.system_id}")

    calls = {"tpm": {"on": rapi.enable_tpm,
                     "off": rapi.disable_tpm,
                     "get": rapi.get_tpm},
             "sb": {"on": rapi.enable_secure_boot,
                    "off": rapi.disable_secure_boot,
                    "get": rapi.get_secure_boot_enable_status}
             }

    #  human readable states
    hr_status = {True: "enabled", False: "disabled"}
    hr_command = {"tpm": "trusted platform module", "sb": "secure boot"}

    current_status = calls[args.command]["get"]()
    print(f"- PASS, Retrieved {hr_command[args.command]} status: {hr_status[current_status]}")

    if args.action == "get":
        return sys.exit(0) if current_status else sys.exit(1)
    elif args.action == "on":
        if current_status:
            print(f"- INFO, System has {hr_command[args.command]} already enabled exiting...")
            sys.exit(0)
        calls[args.command]["on"]()
    elif args.action == "off":
        if not current_status:
            print(f"- INFO, System has {hr_command[args.command]} already disabled exiting...")
            sys.exit(0)
        calls[args.command]["off"]()

    if args.reboot:
        rapi.reboot_server()
    sys.exit(0)


if __name__ == "__main__":
    main()
