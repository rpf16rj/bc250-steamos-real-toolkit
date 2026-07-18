#!/usr/bin/env python
import configparser
import argparse
import os
import sys
import subprocess
from pathlib import Path
from textwrap import dedent

from bc250_smu import Bc250Smu
import bc250_limits as limits

def get_config(path):
    config = configparser.ConfigParser()
    config.read(path)

    frequency = config.getint("overclock", "frequency")
    scale = config.getint("overclock", "scale")
    max_temp = config.getint("overclock", "max_temperature")

    return frequency, scale, max_temp

def write_config(frequency, scale, max_temp, path):
    config = configparser.ConfigParser()
    config["overclock"] = {
        "frequency": frequency,
        "scale": scale,
        "max_temperature": max_temp
    }

    with open(path, "w") as f:
        config.write(f)

def write_service(service_path, config_path):
    unit = dedent(f"""
    [Unit]
    Description=AMD BC-250 CPU Overclock

    [Service]
    ExecStart={sys.executable} {__file__} --apply {config_path}
    Restart=no

    [Install]
    WantedBy=multi-user.target
    """)

    with open(service_path, "w") as f:
        f.write(unit)


def apply_config(path):
    frequency, scale, max_temp = get_config(path)

    if frequency > limits.freq_max or frequency < limits.freq_min:
        raise ValueError("Frequency out of range")

    if scale > limits.scale_max or scale < limits.scale_min:
        raise ValueError("Scale out of range")

    if max_temp > limits.temp_max or max_temp < limits.temp_min:
        raise ValueError("Temperature out of range")

    if os.geteuid() != 0:
        print("Elevating privileges to access PCI config space")
        os.execvp("sudo", ["sudo", sys.executable, __file__, *sys.argv[1:]])

    smu = Bc250Smu(use_flock=True)

    print("Probing SMU Communication...", end = '')
    smu.check_test_message()
    print(" Test Message OK")

    print(f"Applying {frequency} MHz @ Scale {scale}, {max_temp}°C")

    smu.q3_0x8b_set_cpu_max_temperature(max_temp)
    smu.q3_0x8c_set_gpu_max_temperature(max_temp)

    smu.disable_extra_cpu_gpu_voltage(True)

    smu.q3_0x50_scale_f_vid_curve(scale)
    smu.q3_0x8f_set_max_cpu_boost_clk(frequency)


config_path = "/etc/bc250-smu-oc.conf"
service_path = "/etc/systemd/system/bc250-smu-oc.service"

def install_config(path):
    if os.geteuid() != 0:
        print("Elevating privileges to install service")
        os.execvp("sudo", ["sudo", sys.executable, __file__, *sys.argv[1:]])

    frequency, scale, max_temp = get_config(path)
    write_config(frequency, scale, max_temp, config_path)
    print(f"written config to {config_path}")

    write_service(service_path, config_path)
    print(f"written service to {service_path}")
    print(f"\nenable using: systemctl enable bc250-smu-oc")

def uninstall_config():
    subprocess.run(["sudo", "rm", "-f", config_path])
    print(f"Deleted {config_path}")
    subprocess.run(["sudo", "rm", "-f", service_path])
    print(f"Deleted {service_path}")


def main() -> None:
    global smu

    parser = argparse.ArgumentParser(description = "Apply CPU overclock settings on AMD BC-250")

    parser.add_argument("-a", "--apply", action="store_true", help="Apply overclock configuration")
    parser.add_argument("-i", "--install", action="store_true", help="Install overclock configuration as service")
    parser.add_argument("-u", "--uninstall", action="store_true", help="Uninstall configuration")
    parser.add_argument("path", type=Path, nargs="?", help="configuration path")

    args = parser.parse_args()

    if args.uninstall:
        uninstall_config()
        return

    if args.path is None:
        parser.error("Path is required!")

    if args.apply:
        apply_config(args.path)

    if args.install:
        install_config(args.path)

if __name__ == "__main__":
    main()
