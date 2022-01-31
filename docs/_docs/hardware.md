---
title: Hardware
permalink: /docs/hardware/
redirect_from: /docs/hardware.md
---

## Hardware used

This is the hardware I'm using to create the cluster:

- [4 x Raspberry Pi 4 - Model B (4 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1100-raspberry-pi-4-modelo-b-4gb-765756931182.html) for the kuberenetes cluster (1 master node and 3 workers).
- [1 x Raspberry Pi 4 - Model B (2 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1099-raspberry-pi-4-modelo-b-2gb-765756931175.html) for creating a router for the lab environment connected via wifi to my home network and securing the access to my lab network.
- [4 x SanDisk Ultra 32 GB microSDHC Memory Cards](https://www.amazon.es/SanDisk-SDSQUA4-064G-GN6MA-microSDXC-Adaptador-Rendimiento-dp-B08GY9NYRM/dp/B08GY9NYRM) (Class 10) for installing Raspberry Pi OS for enabling booting from USB (update Raspberry PI firmware and modify USB partition)
- [4 x Samsung USB 3.1 32 GB Fit Plus Flash Disk](https://www.amazon.es/Samsung-FIT-Plus-Memoria-MUF-32AB/dp/B07HPWKS3C) 
- [1 x Kingston A400 SSD Disk 480GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N0TQPQB)
- [3 x Kingston A400 SSD Disk 240GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)
- [4 x Startech USB 3.0 to SATA III Adapter](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro) for connecting SSD disk to USB 3.0 ports.
- [1 x GeeekPi Pi Rack Case](https://www.amazon.es/GeeekPi-Raspberry-Ventilador-refrigeraci%C3%B3n-disipador/dp/B07Z4GRQGH/ref=sr_1_11). It comes with a stack for 4 x Raspberry Pi’s, plus heatsinks and fans)
- [1 x SSD Rack Case](https://www.aliexpress.com/i/33008511822.html)
- [1 x Negear GS108-300PES](https://www.amazon.es/Netgear-GS108E-300PES-conmutador-gestionable-met%C3%A1lica/dp/B00MYYTP3S). 8 ports GE ethernet manageable switch (QoS and VLAN support)
- [1 x ANIDEES AI CHARGER 6+](https://www.tiendatec.es/raspberry-pi/raspberry-pi-alimentacion/796-anidees-ai-charger-6-cargador-usb-6-puertos-5v-60w-12a-raspberry-pi-4712909320214.html). 6 port USB power supply (60 W and max 12 A)
- [5 x Ethernet Cable](https://www.aliexpress.com/item/32821735352.html). Flat Cat 6,  15 cm length
- [5 x USB-C charging cable with ON/OFF switch](https://www.aliexpress.com/item/33049198504.html).


## Storage benchmarking

The performance of the different storage configurations for the Raspberry Pi has been tested.

1) Internal SDCard: [SanDisk Ultra 32 GB microSDHC Memory Cards](https://www.amazon.es/SanDisk-SDSQUA4-064G-GN6MA-microSDXC-Adaptador-Rendimiento-dp-B08GY9NYRM/dp/B08GY9NYRM) (Class 10)
2) Flash Disk USB 3.0: [Samsung USB 3.1 32 GB Fit Plus Flash Disk](https://www.amazon.es/Samsung-FIT-Plus-Memoria-MUF-32AB/dp/B07HPWKS3C)
3) SSD Disk [Kingston A400 480GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N0TQPQB) + USB3 to SATA Adapter [Startech USB 3.0 to SATA III](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro) 
4) SCSI using a Target SCSI running on Raspberry PI using as USB 3.0 SSD disk

### Testing procedure

Sequential and random I/O tests have been executed with the different storage configurations. 

For the testing a tweaked version of the script provided by James A. Chambers (https://jamesachambers.com/) has been used

Tests execution has been automated with Ansible. See `pi-storage-benchmark` [repository](https://github.com/ricsanfre/pi-storage-benchmark) for the details of the testing procedure and the results.

#### Sequential I/O performance

Test sequential I/O with `dd` and `hdparam` tools. `hdparm` can be installed through `sudo apt install -y hdparm`


- Read speed (Use `hdparm` command)
    
  ```shell
  sudo hdparm -t /dev/sda1
    
  Timing buffered disk reads:  72 MB in  3.05 seconds =  23.59 MB/sec

  sudo hdparm -T /dev/sda1
  Timing cached reads:   464 MB in  2.01 seconds = 231.31 MB/sec
  ```

  It can be combined in just one command:

  ```shell
  sudo hdparm -tT --direct /dev/sda1

  Timing O_DIRECT cached reads:   724 MB in  2.00 seconds = 361.84 MB/sec
  Timing O_DIRECT disk reads: 406 MB in  3.01 seconds = 134.99 MB/sec
  ```

- Write Speed (use `dd` command)

  ```shell
  sudo dd if=/dev/zero of=test bs=4k count=80k conv=fsync

  81920+0 records in
  81920+0 records out
  335544320 bytes (336 MB, 320 MiB) copied, 1,86384 s, 180 MB/s
  ```

#### Random I/O Performance

Tools used `fio` and `iozone`.

- Install required packages with:

  ```shell
  sudo apt install iozone3 fio
  ```

- Check random I/O with `fio`

  Random Write

  ```shell
  sudo fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=80M --readwrite=randwrite
   ```

  Random Read

  ```shell
  sudo fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=80M --readwrite=randread
   ```

- Check random I/O with `iozone`

  ```shell
  sudo iozone -a -e -I -i 0 -i 1 -i 2 -s 80M -r 4k
  ```

### Performance Results

Average-metrics obtained during the tests removing the worst and the best result can be found in the next table and the following graphs:

|           | Disk Read (MB/s) | Cache Disk Read (MB/s) | Disk Write (MB/s) | 4K Random Read (IOPS) | 4K Random Read (KB/s) | 4K Random Write (IOPS) | 4K Random Write (KB/s) | 4k read (KB/s) | 4k write (KB/s) | 4k random read (KB/s) | 4k random write (KB/s) | Global Score   |
| --------- | ---------------- | ---------------------- | ----------------- | --------------------- | --------------------- | ---------------------- | ---------------------- | -------------- | --------------- | --------------------- | ---------------------- | ------- |
| SDCard    | 41.89            | 39.02                  | 19.23             | 2767.33               | 11071.00              | 974.33                 | 3899.33                | 8846.33        | 2230.33         | 7368.67               | 3442.33                | 1169.67 |
| FlashDisk | 55.39            | 50.51                  | 21.30             | 3168.40               | 12675.00              | 2700.20                | 10802.40               | 14842.20       | 11561.80        | 11429.60              | 10780.60               | 2413.60 |
| SSD       | 335.10           | 304.67                 | 125.67            | 22025.67              | 88103.33              | 18731.33               | 74927.00               | 31834.33       | 26213.33        | 17064.33              | 29884.00               | 8295.67 |
| iSCSI     | 70.99            | 71.46                  | 54.07             | 5104.00               | 20417.00              | 5349.67                | 21400.00               | 7954.33        | 7421.33         | 6177.00               | 7788.33                | 2473.00 |
{: .table }

- Sequential I/O

  ![sequential_i_o](/assets/img/benchmarking_sequential_i_o.png)


- Random I/O (FIO)

  ![random_i_o](/assets/img/benchmarking_random_i_o.png)

- Random I/O (IOZONE)

  ![random_i_o_iozone](/assets/img/benchmarking_random_i_o_iozone.png)


- Global Score

  ![global_score](/assets/img/benchmarking_score.png)


1) Clearly `SSD` with USB3.0 to SATA adapter beats the rest in all performance tests.
2) `SDCard` obtains worst metrics than `FlashDisk` and `iSCSI`
2) `FlashDisk` and `iSCSI` get simillar performance metrics 

The performace obtained using local attached USB3.0 Flash Disk is quite simillar to the one obtained using iSCSI with a SSD Disk as central storage.
