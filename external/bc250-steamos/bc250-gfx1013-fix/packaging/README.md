# Packaging status

There are no native packages yet. The supported path is `install.sh` (source build, Fedora 43,
see the top-level README).

## Planned native packages

If/when this graduates from alpha, the Fedora/Bazzite channel would split into:

- `bc250-gfx1013-v33`: kernel module, initramfs/BLS profile, and activation generator;
- `mesa-gfx1013`: private x86_64 RADV build under `/opt` (plus a matching i686 build for
  Steam/Proton);
- `bc250-gfx1013-tools`: status and rollback tooling.

Ground rules carried over from the installer: never replace the distro's Mesa packages, never
touch the stock kernel module or initramfs, and keep the patched driver selected only on the
patched boot entry.
