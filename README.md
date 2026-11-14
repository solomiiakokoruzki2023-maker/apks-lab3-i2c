# apks-lab3-i2c
# Лабораторна робота №3. Послідовний протокол I2C на ПЛІС

**Дисципліна:** Автоматизоване проєктування комп'ютерних систем
**Виконала:** Кокорузь Соломія, група КІ-405
**Варіант:** 11 (протокол I2C, мова VHDL)

## Опис
I2C Master на VHDL: 7-бітна адреса, передача й прийом одного байта за транзакцію, без clock stretching. Тестбенч містить поведінкову модель Slave (адреса 0x50) і перевіряє три сценарії: запис байта 0x3C, читання байта 0xA5 та NACK при неправильній адресі.

## Структура
- `src/i2c_master.vhd` - модуль I2C Master
- `tb/i2c_master_tb.vhd` - тестбенч зі Slave-моделлю
- `docs/` - діаграма станів та скріншоти

## Інструменти
GHDL (симуляція), Vaporview / GTKWave (осцилограми), Yosys + nextpnr-ice40 (синтез і Fmax). Vivado не використовувався.

## Запуск симуляції
```
ghdl -a --std=08 src/i2c_master.vhd tb/i2c_master_tb.vhd
ghdl -e --std=08 i2c_master_tb
ghdl -r --std=08 i2c_master_tb --vcd=wave.vcd
```
Очікуваний результат: TEST 1, TEST 2, TEST 3 PASSED.

## Запуск синтезу
```
mkdir build
ghdl --synth --std=08 --out=verilog src/i2c_master.vhd -e i2c_master > build/i2c_master_syn.v
yosys -p "read_verilog build/i2c_master_syn.v; synth_ice40 -top i2c_master -json build/i2c_master.json; stat"
nextpnr-ice40 --hx8k --package ct256 --json build/i2c_master.json --freq 50 --pcf-allow-unconstrained
```

## Результати синтезу (Lattice iCE40 HX8K)
| Показник | Значення |
|---|---|
| LUT (SB_LUT4) | 98 |
| Тригери | 55 |
| Fmax | 154.01 MHz (PASS at 50 MHz) |