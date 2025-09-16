# LTE Recovery Script for GL-XE300_V1.0 Router Board

This script resets and brings up a Quectel EP06-A LTE modem using `uqmi`.

## What It Does

- Kills stuck `uqmi` processes
- Stops the active PDP session (with timeout)
- Blanks and restores the APN
- Forces `raw_ip=Y` mode
- Brings interface down and up cleanly
- Confirms WAN is working (IP + route + ping)

## Why I Made This

Most LTE recovery tools are locked behind vendor-specific web GUIs.  
This script is built for **OpenWRT 24.10.0** and is intended for users running **command-line only** with no GUI.

Use cases include:

- Deployments where modem control must be done over shell
- Cron-based or watchdog-based recovery without manual intervention
- Off-grid or solar-powered systems where the LTE radio is **only active at certain times of day**

If you're running raw OpenWRT and want reliable LTE recovery on CLI, this is for you.

## Requirements

System must be flashed to **OpenWRT 24.10.0** with the **Quectel EP06-A** modem installed.  
Assumes modem interface is named `wwan` and located at `/dev/cdc-wdm0`.

The script uses an APN of `mobile`, which is valid for **EIOT Club SIM cards** as of this commit.  
This SIM was selected for its plug-and-play compatibility with OpenWRT and `uqmi`, requiring no manual registration or configuration.

Assumes WAN port has internet access during the first run so the required packages can be installed.

Install required packages:

```bash
opkg update && opkg install uqmi ip-full iputils-ping uci

