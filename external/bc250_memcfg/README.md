# bc250_memcfg
BC-250 tool to set CMOS BIOS memory configuration from linux.
Works also with original P3.00 and P5.00 BIOS, no modded BIOS needed.

Vendored from [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg)
for use by `bc250-steamos-real-toolkit`'s RAM/VRAM Split feature. Compiled
locally from this vendored source at install time (`gcc -Os -s main.cpp -o
bc250memcfg`) rather than downloading a prebuilt release binary.

## Usage

The most useful parameter to set is probably VRAM size (`UMA_SIZE`).

You run it as root with one parameter and value like this:

```
sudo ./bc250memcfg UMA_SIZE 512
setting UMA_SIZE to 512
```
and then reboot the machine.

For `UMA_SIZE` you can use any sensible value >= 256, the number gets
automatically aligned to 16MB steps.

Running without parameters prints all values for all tunable parameters.

You can also tune memory timings (like tREF) but it may affect stability and
no significant gains were confirmed. For more info see
https://github.com/NexGen-3D-Printing/SteamMachine/blob/main/Memory-Timings-Explained.txt

This tool writes to battery backed CMOS RAM. To revert to default values
clear CMOS by jumper on the board and/or by removing battery.

This tool does not require modified BIOS; it was confirmed that it works
both with P3.00 and P5.00 original BIOS so no custom BIOS is needed if you
just want to modify VRAM size.

## Credits

Initial source version of this utility was published on Discord in the Mem
Timing Utility topic by ethkey. It printed all parameters and hardcoded a
'demo' write of tREF that was causing segfaults. fanoush fixed the crash and
added code to set a value for each tunable parameter via the command line.
