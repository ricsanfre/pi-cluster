---
title: Raspberry PI Utilities
permalink: /docs/pi-commands/
description: Raspberry PI specific commands available in Ubuntu OS for getting information about temperature and throttled status.
last_modified_at: "25-02-2022"
---

Raspberry PI OS contains several specific utilities such as `vcgencmd` that are also available in Ubuntu 24.04 through the package [`libraspberrypi-bin`](https://packages.ubuntu.com/jammy/libraspberrypi-bin)

## Utility vcgencmd

`vcgencmd` tool is used to output information from the VideoCore GPU on the Raspberry Pi.

A full description of the available commands and information extracted can be found [here](https://www.raspberrypi.org/documentation/computers/os.html#vcgencmd).

```shell
vcgencmd get_throttled
```

Returns the throttled state of the system. The output of the command is a bit pattern. It can be decoded using this [script](https://gist.github.com/aallan/0b03f5dcc65756dde6045c6e96c26459)

```shell
vcgencmd measure_temp
```

Get Raspberry Pi GPU temperature in ºC.

```shell
vcgencmd get_mem arm/gpu
```

Get RAM memmory assigned to CPU/GPU




