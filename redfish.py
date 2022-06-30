#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

"Provides selected configuration possibilites via REDFISH REST management api."

import json
import sys
import time
import warnings
import argparse
import requests


warnings.filterwarnings("ignore")


class NoTpmModuleException(KeyError):
    "To be raised in case user performs tpm operation on system that does not have tpm module."


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
        self._pending_bios_attrs = {}

    def _request(self, method: str, endpoint: str, check=True, timeout=HTTP_RESPONSE_TIMEOUT, **kwargs):
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
                                             timeout=timeout,
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
        """Returns True if BMC seems to be Supermicro"""
        return self.system_id == "1"

    @property
    def is_dell(self) -> bool:
        """Returns True if BMC seems to be Dell"""
        return self.system_id == "System.Embedded.1"

    def check_connectivity(self):
        """Checks if base url https://address/redfish/v1 is accesible
        for further redfish operations.
        """
        try:
            self._request("get", "", check=False, timeout=1)
        except requests.exceptions.RequestException:
            return False
        return True

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
            For changes to be to applied for dell finalize_bios_settings should be called.
        """
        # supermicro has different payload
        if self.is_supermicro:
            payload = {"SecureBoot": "Enabled"}
            response = self.patch_secure_boot(payload)
            print(f"- PASS, Secure boot command successful, code return is {response.status_code}")
        else:
            self._pending_bios_attrs["SecureBoot"] = "Enabled"

    def disable_secure_boot(self):
        """Disables secure boot for given system.

        Note:
            For changes to be to applied for dell finalize_bios_settings should be called.
        """
        # supermicro has different payload
        if self.is_supermicro:
            payload = {"SecureBoot": "Disabled"}
            response = self.patch_secure_boot(payload)
            print(f"- PASS, Secure boot command successful, code return is {response.status_code}")
        else:
            self._pending_bios_attrs["SecureBoot"] = "Disabled"

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
        Note: For changes to be applied finalize_bios_settings should be called.
        """
        # TODO: Check what is payload/endpoint for supermicro
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")
        self._pending_bios_attrs["TpmSecurity"] = "On"

    def disable_tpm(self):
        """Disables trusted platform module support for given system.
        Note: For changes to be applied finalize_bios_settings should be called.
        """
        # TODO: Check what is payload/endpoint for supermicro
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")

        self._pending_bios_attrs["TpmSecurity"] = "Off"

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
        if "TpmSecurity" not in data["Attributes"]:
            raise NoTpmModuleException("No 'TpmSecurity' found in system bios attributes. "
                                       "Please ensure tpm module installed on the system.")

        return data["Attributes"]["TpmSecurity"] == "On"

    def finalize_bios_settings(self):
        """Finalizes setting pending bios configuration by patching /Bios/Setting
        endpoint and creating bios_config_job.
        """
        if self.is_supermicro:
            raise NotImplementedError("Not yet implemented for supermicro.")
        if not self._pending_bios_attrs:
            return
        response = self.patch_bios_settings({"Attributes": self._pending_bios_attrs})
        print(f"- PASS, Bios patch command successful, code return is {response.status_code}")
        # Changes in dell bios settings require creation of config job for them to take effect
        self.create_bios_config_job()

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


    epilog = ("Note: Tool will not perform reboot by default. It is user "
    "decision if operation performed requires it.\n"
    "Get value operation ex. '--tpm get' allows only single"
    "option to be taken via single call (--tpm get --sb get will not work).\n\n"
    "Examples:\n"
    "> %(prog)s.py --sb on -u "
    "calvin -p rootpass --ip 10.22.22.139 -r\n\n"
    "> %(prog)s.py --tpm get -u "
    "calvin -p rootpass --ip 10.22.22.139\n\n"
    "> %(prog)s.py --tpm off --sb off -u "
    "calvin -p rootpass --ip 10.22.22.139")

    parser = argparse.ArgumentParser(description="This script utilizes Redfish API to "
                                                 "perform management operations on "
                                                 "iDRAC or SUPERMICRO machine.",
                                                 formatter_class=CustomFormatter,
                                                 epilog=epilog)
    parser.add_argument("--ip", help="MGMT IP address.", required=True)
    parser.add_argument("-u", "--user", help="MGMT username.", required=True)
    parser.add_argument("-p", "--password", help="MGMT password.", required=True)
    parser.add_argument("--proxy", help="Proxy server for traffic redirection.", required=False)
    parser.add_argument("-r", "--reboot",
                        help="Rebot remote machine after operation performed.",
                        required=False,
                        action="store_true")
    parser.add_argument("-v", "--verbose",
                        help="Extend verbosity.",
                        required=False,
                        action="store_true",
                        default=False)
    parser.add_argument("--sb",
                        help="Secure boot configuration.",
                        choices=["on", "off", "get"],
                        required=False)
    parser.add_argument("--tpm",
                        help="Trusted module platform configuration.",
                        choices=["on", "off", "get"],
                        required=False)

    return parser.parse_args()


def main():
    "Main execution function"
    args = parse_args()
    if not args.tpm and not args.sb:
        print("\n- FAIL, Incorrect parameters run: -h/--help")
        sys.exit(1)

    rapi = RedfishAPI(args.ip,
                      args.user,
                      args.password,
                      verbose=args.verbose)

    # try to access endpoint without proxy, if can't reach endpoint try to set proxy
    if not rapi.check_connectivity():
        if not args.proxy:
            print("\n- FAIL, Redfish is inaccessible. Please ensure ip address is correct.")
            sys.exit(1)
        print(f"- INFO, base url {rapi.base_url} inaccessible without proxy...")
        proxy = {}
        proxy["http"] = args.proxy
        proxy["https"] = args.proxy
        rapi.proxy = proxy
        if not rapi.check_connectivity():
            print("\n- FAIL, Redfish is inaccessible via proxy. Please ensure address is correct.")
            sys.exit(1)

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

    for name, functions in calls.items():
        option = getattr(args, name)
        if not option:
            continue

        current_status = functions["get"]()
        print(f"- PASS, Retrieved {hr_command[name]} status: {hr_status[current_status]}")

        if option == "get":
            return sys.exit(0) if current_status else sys.exit(1)
        elif option == "on":
            if current_status:
                print(f"- INFO, System has {hr_command[name]} already enabled exiting...")
                sys.exit(0)
            functions["on"]()
        elif option == "off":
            if not current_status:
                print(f"- INFO, System has {hr_command[name]} already disabled exiting...")
                sys.exit(0)
            functions["off"]()

    rapi.finalize_bios_settings()

    if args.reboot:
        rapi.reboot_server()
    sys.exit(0)


if __name__ == "__main__":
    main()
