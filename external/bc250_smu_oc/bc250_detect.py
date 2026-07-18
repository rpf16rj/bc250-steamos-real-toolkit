#!/usr/bin/env python
import struct
import time
import configparser
import argparse
import atexit
import os
import sys
from pathlib import Path

from bc250_smu import Bc250Smu
from stress_helper import stress_start, stress_stop
import bc250_limits as limits

def vid_predict(clock, scale):
    if clock < 3000:
        raise ValueError("cannot predict vid for clocks below 3 GHz")
    p = -1.519 + scale * 0.004325
    q = 2800.0 - (scale * 10.0)
    return 0.0003 * clock * clock + p * clock + q

def vid_predict_delta(clock_cur, clock_next, scale_cur, scale_next):
    if clock_cur < 3000 or clock_next < 3000:
        return 0
    return vid_predict(clock_next, scale_next) - vid_predict(clock_cur, scale_cur)

def vid_predict_relative(clock_cur, clock_next, scale_cur, scale_next, vid_cur):
    # We scale our predction by 0.75 to bias it towards the upper limit
    return vid_cur + (vid_predict_delta(clock_cur, clock_next, scale_cur, scale_next) * 0.75)

def smu_apply(clock, scale):
    if clock > limits.freq_max or scale < limits.scale_min or scale > limits.scale_max:
        raise ValueError("Parameters out of bounds")

    smu.q3_0x50_scale_f_vid_curve(scale)
    smu.q3_0x8f_set_max_cpu_boost_clk(clock)

# Detect active cores by determining if their frequency is managed by the smu
def detect_active_cores():
    cores = []

    smu_apply(3500, 0)
    stress_start()
    time.sleep(1)

    print("Detected Active Cores: ", end='')

    for i in range(0, 8):
        clk = smu.q3_0x43_get_core_freq(i)
        if clk > 3000:
            print(i, end='')
            cores.append(True)
        else:
            print('X', end='')
            cores.append(False)

    print('')
    stress_stop()

    return cores

def check_throttling(threshold, cores):
    for i in range(0, 8):
        clk = smu.q3_0x43_get_core_freq(i)
        if cores[i] == True and clk < threshold:
            return True

    return False

config_path = "overclock.conf"
def write_config(f_safe, scale_safe, max_temperature):
    config = configparser.ConfigParser()
    config["overclock"] = {
        "frequency": f_safe,
        "scale": scale_safe,
        "max_temperature": max_temperature
    }

    with open(config_path, "w") as f:
        config.write(f)

def revert_defaults():
    smu.q3_0x8f_set_max_cpu_boost_clk(3500)
    smu.q3_0x50_scale_f_vid_curve(0)
    smu.disable_extra_cpu_gpu_voltage(False)
    smu.q3_0x8b_set_cpu_max_temperature(100)
    smu.q3_0x8c_set_gpu_max_temperature(100)

    print("Restored Default Parameters")

def detect(f_target, v_max, t_max):
    f_step = 100
    delay_short = 0.25
    delay_long = 10

    f_start = 3500 + (f_target % f_step)
    f_test = f_start
    f_safe = f_start
    v_scale_test = 0
    v_scale_safe = 0
    v_meas = 0

    f_throttling_threshold = 50

    # set safe temperature limits
    smu.q3_0x8b_set_cpu_max_temperature(t_max)
    smu.q3_0x8c_set_gpu_max_temperature(t_max)
    # always disable extra voltage
    smu.disable_extra_cpu_gpu_voltage(True)

    # Detect active cores for throttling detection
    cores = detect_active_cores()

    print(f"Attempting to reach {f_target} MHz @ {v_max} mV, {t_max}°C")

    while True:
        smu_apply(f_test, v_scale_test)

        stress_start()
        time.sleep(delay_short)

        v_meas = smu.q3_0x36_get_current_cpu_voltage()
        if v_meas > v_max:
            stress_stop()
            v_scale_test -= max(int((v_meas - v_max) / 6.0), 1) # estimate the required undervolt
            continue

        print(f"Stress Testing {f_test} MHz @ {v_meas} mV")
        time.sleep(delay_long)

        if(check_throttling(f_test - f_throttling_threshold, cores)):
            stress_stop()
            print("Aborting because thorttling was detected")
            break

        stress_stop()

        f_safe = f_test
        v_scale_safe = v_scale_test
        write_config(f_safe, v_scale_safe, t_max)

        # Main exit condition
        if not f_safe < f_target:
            break

        f_test += f_step

        v_pred = vid_predict_relative(f_safe, f_test, v_scale_safe, v_scale_test, v_meas)
        while(v_pred > v_max):
            v_scale_test -= 1
            v_pred = vid_predict_relative(f_safe, f_test, v_scale_safe, v_scale_test, v_meas)

    print(f"\nFinal Result: {f_safe} MHz @ {v_meas} mV using scale {v_scale_safe}")
    smu_apply(f_safe, v_scale_safe)

def int_freq(value):
    value = int(value)
    if value < limits.freq_min:
        print("Cannot overclock below stock frequency!")
        raise argparse.ArgumentError()
    if value > limits.freq_max:
        print("Target frequency is too high!")
        raise argparse.ArgumentError()
    return value

def int_vid(value):
    value = int(value)
    if value < limits.vid_min:
        print(f"It is not allowed to go below {limits.vid_min} mV Vid!")
        raise argparse.ArgumentError()
    if value > limits.vid_max:
        print(f"It is not allowed to go above {limits.vid_max} mV Vid!")
        raise argparse.ArgumentError()
    return value

def int_temp(value):
    value = int(value)
    if value < limits.temp_min:
        print("Specify positive integers for temperature limit!")
        raise argparse.ArgumentError()
    if value > limits.temp_max:
        print(f"Temperature limit cannot be above {limits.temp_max} °C!")
        raise argparse.ArgumentError()
    return value

def main() -> None:
    global smu
    global config_path

    parser = argparse.ArgumentParser(description = "Detect CPU overclock settings on AMD BC-250")
    parser.add_argument("-f", "--frequency", type=int_freq, metavar="MHz", required="True", help="Target Overclock Frequency in MHz")
    parser.add_argument("-v", "--vid", type=int_vid, metavar="mV", required="True", help="CPU Core Voltage Limit in mV")
    parser.add_argument("-t", "--temp", type=int_temp, metavar="°C", default=90, help="CPU and GPU Temperature Limit in °C (90 °C by default)")
    parser.add_argument("-k", "--keep", action="store_true", help="Keep Overclock after Exiting")
    parser.add_argument("-c", "--config", type=Path, metavar="path", default="overclock.conf", help="Path to configuration file, (overclock.conf by default)")

    args = parser.parse_args()
    config_path = args.config

    if os.geteuid() != 0:
        print("Elevating privileges to access PCI config space")
        os.execvp("sudo", ["sudo", sys.executable, __file__, *sys.argv[1:]])

    smu = Bc250Smu(use_flock=True)
    atexit.register(revert_defaults)

    print("Probing SMU Communication...", end = '')
    smu.check_test_message()
    print(" Test Message OK")

    detect(args.frequency, args.vid, args.temp)
    
    if args.keep:
	    atexit.unregister(revert_defaults)

    print(f"Done, config file was written to {config_path}")

if __name__ == "__main__":
    main()
