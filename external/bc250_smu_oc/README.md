# bc250_smu_oc
Tool to modify the BC-250s CPU Parameters via SMU ( System Management Unit) messages with help of bc250_smu library.  
Useful for Overclocking & Undervolting of BC-250. 

## DISCLAIMER

Overclocking is done at your own risk! Failure to follow the full instructions provided below will result in damage to your hardware!   
Increasing the CPU frequency without undervolting will result in uncapped Vid scaling & destroy your hardware! (I have managed to permanently brick one BC-250 in this way)   
Always make sure that CPU core voltage ("Vid") does not exceed 1.325 V under any circumstances! Monitor your hardware & always do stress testing after changing parameters!   

## Software Support

OS: Tested on Ubuntu 25.10, Bazzite, Arch Linux   
Service Manager: systemd   
Firmware: Verified on BIOS V3 & V5   

## Installation 

1) Install `stress` CPU stress testing tool using you distributions package manager

2) Use `pip` or `pipx` depending on how your OS manages python packages to install the cli

<pre>
git clone https://github.com/bc250-collective/bc250_smu_oc.git
cd bc250_smu_oc
pip[x] install .
</pre>

## Usage

The tools will automatically elevate privileges if required.

### bc250-detect

<pre>usage: bc250-detect [-h] -f MHz -v mV [-t °C] [-k] [-c path]

Detect CPU overclock settings on AMD BC-250

options:
  -h, --help           show this help message and exit
  -f, --frequency MHz  Target Overclock Frequency in MHz
  -v, --vid mV         CPU Core Voltage Limit in mV
  -t, --temp °C        CPU and GPU Temperature Limit in °C (90 °C by default)
  -k, --keep           Keep Overclock after Exiting
  -c, --config path    Path to configuration file, (overclock.conf by default) </pre>

### bc250-apply

<pre>usage: bc250-apply [-h] [-a] [-i] path

Apply CPU overclock settings on AMD BC-250

positional arguments:
  path           configuration path

options:
  -h, --help     show this help message and exit
  -a, --apply    Apply overclock configuration
  -i, --install  Install overclock configuration as service  </pre>

## Overclocking 

To begin, use `bc250-detect` to determine a stable overclock for your system. It will create `overclock.conf` with the detected parameters.   
You can try these settings to reach 4 GHz @ 1275 mV on your system. Use the --keep flag to keep the overclock after the detection finishes. This will also set the CPU & GPU Temperature limits to a safer 90 °C (100 °C is stock)  

<pre>bc250-detect --frequency 4000 --vid 1275 --keep</pre>

If your system crashes during the detection, try rerunning the command with `--vid 1300`. If it still is not stable, reduce the target frequency. To be easy on your system, you should stay below 1300 mV Vid.

Once you are happy with your settings & have done more thorough stability testing (read [Stability testing](#stability-testing) if you want to learn more), you can apply the settings on startup:

<pre>bc250-apply --install overclock.conf
systemctl enable bc250-smu-oc</pre> 

## Undervolting 

If you just want to undervolt without increasing the frequency:
<pre>bc250-detect --frequency 3500 --vid 1000 --keep</pre>

The stock core voltage at 3.5 GHz is around 1180 mV. 

## Monitoring & Loading your System

To monitor SMU metrics: [amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top) or [kernel patch](https://github.com/bc250-collective/amd_smu_reverse_engineering/tree/main/patches)   
I recommend `amdgpu_top` because it does not require recompilation of the kernel.  

![amdgpu_top screenshot](/figures/amdgpu_top.png)

To monitor effective CPU clocks (useful for detecting clock stretching):   
`watch -n 1 "cat /proc/cpuinfo | grep MHz"`


## Why is my CPU throttling (when I load the GPU)?

Do not increase the temperature limit in response to this issue. If your thermal solution is inadequate to cool the CPU, improve it.   
Loading the GPU will always reduce the thermal headroom of the CPU as they share a die and by extension a cooler. This will result in thermal throttling on the CPU.   
You should still overclock the CPU, because even at stock frequency (3.5 GHz) overclocking will lead to a significant undervolt (around 200 mV) which will greatly improve efficiency.   
So it is a good idea to overclock, set a sensible temperature limit & let the SMU manage the thermals.   

If you want to target high clocks even when the GPU is loaded, watercooling might be necessary.   

## Stability testing

There is a lot of way to stress your system, but in the end, it's a mix of synthetic and real-world usage.

For synthetic testing, there is a lot of different tools, but popular ones (that run on linux and in use by bc250 community):
- OCCT (Good tests are 3D adaptive test and CPU+RAM. Always choose variable load, because it's closer resemble real world usage)
- Prime95 (Thanks @Panasonic2288 for remiding me about it)

Separate note about Furmark, it's good GPU stress test. But it doesn't check stability per se. Use it for testing your power delivery and cooling.  

As for real-world usage, it's harder to tell, but just go, and do the stuff that you do or plan to do regularly on your bc250.  
E.g. if you game: just try playing them, and check if there is any artifacts/bugs/crashes.
if you watch videos - do it, etc.  


## Advanced Overclocking and system control 

The `bc250_smu` libary defines more SMU messages for overclocking. Be aware that the SMU does minimal validity checking & you have full control over the system!

## Vid Curves for Reference

![vid curve](/figures/vidcurve.png)

## Results on my system

### 3.5 GHz
Passmark Score: 13615   
Single Thread: 2143   

### 4.1 GHz @ 1.3 V
Passmark Score: 15510   
Single Thread: 2506   
[Benchmark](https://www.passmark.com/baselines/V11/display.php?id=510970430450)
