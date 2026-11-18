# MANUAL DE COM FLASHEJAR PLAQUES ESP32 DESDE CODI FONT by Cristina

## 1. Instal·lar dependències

Necessitarem el següent entorn per començar:
* Python3 (and pip)
* Visual Studio Code (es pot fer amb terminal però en aquest cas ho farem així al haver més documentació i facilitats)
* esptool
* git (òbviament)
* **Suficient** espai a disc (sino no s'instalarà tot!!)

Primer instal·larem les dependències
```shell
sudo apt install python3 python3-pip esptool code git
pip3 install --upgrade esptool
```

I després clonarem el repositori d'on ve el firmware
```shell
git clone https://github.com/meshtastic/firmware.git
cd firmware && git submodule update --init
git pull --recurse-submodules
```

## 2. Configurar el VS Code

Ara, al VS obriràs la carpeta principal del repositori (que haurà de ser firmware) en la part esquerra de l'editor. D'aquesta manera quan obris un terminal serà directament en la nostra nova ruta base.
Per flashejar aquestes plaques farem ús de les extensions de PlatformIO i ESP Crash Decoder (ambdues et seran recomanades quan obris la carpeta base del repositori que acabes de clonar). 

Atenció!! És possible que no et surti directament la de PlatformIO i et surti la de pioarduino IDE (em va passar). Jo et recomanaria que et utilitzis PlatformIO ja que aquest document es fa utilitzant aquesta extensió.

Un cop hagis instal·lat les extensions pertanyents hauràs de configurar, compilar i instal·lar el firmware. Primer començarem per tenir enllestit el firmware, llest per flashejar

## 3. Configurar, compilar i instal·lar el firmware

### 3.1 Configurar

En el nostre cas, pel model de les nostres plaques hem de configurar l'entorn **tbeam** en **platformio.ini**. Per fer això, cal obrir el fitxer i canviar-ho (és literalment la cinquena línia)


### 3.2 Compilar

Després cal obrir una terminal de PlatformIO (farem ús de la extensió) i posar la següent comanda (també instal·lant el paquet primer):
```shell
pio pkg install -e tbeam
pio run -e tbeam
```

Comprovem que es reconeixen les plaques connectades:
```shell
pio device list
```
Que, en el meu cas, l'output que tinc és el següent:
```shell
/dev/ttyS3
----------
Hardware ID: n/a
Description: n/a

/dev/ttyS2
----------
Hardware ID: n/a
Description: n/a

/dev/ttyS1
----------
Hardware ID: n/a
Description: n/a

/dev/ttyS0
----------
Hardware ID: n/a
Description: n/a

/dev/ttyACM3
------------
Hardware ID: USB VID:PID=1A86:55D4 SER=5874105917 LOCATION=1-3.1:1.0
Description: USB Single Serial

/dev/ttyACM2
------------
Hardware ID: USB VID:PID=1A86:55D4 SER=5874107375 LOCATION=1-3.2:1.0
Description: USB Single Serial

/dev/ttyACM1
------------
Hardware ID: USB VID:PID=1A86:55D4 SER=576F000200 LOCATION=1-3.3:1.0
Description: USB Single Serial

/dev/ttyACM0
------------
Hardware ID: USB VID:PID=1A86:55D4 SER=5887017665 LOCATION=1-3.4:1.0
Description: USB Single Serial
```
També (molt important) ens hem d'enrecordar de posar el nostre usuari al grup _dialout_ per poder executar les comandes del platformio:
```shell
sudo usermod -aG dialout "$USER"
```

### 3.3 Instal·lar

Per instal·lar, agafarem tots els dispositius que hem rebut pel device list i els flashejarem a la vegada:
```shell
pio run -e tbeam -t upload --upload-port /dev/ttyACM0
pio run -e tbeam -t upload --upload-port /dev/ttyACM1
pio run -e tbeam -t upload --upload-port /dev/ttyACM2
pio run -e tbeam -t upload --upload-port /dev/ttyACM3
```

I d'aquesta forma, ja tenim les nostres 4 plaques flashejades :D !!