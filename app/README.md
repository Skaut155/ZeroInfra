# 🚀 Guía de Instalación y Configuración del Entorno Local

Esta guía detalla los pasos necesarios para clonar, configurar el entorno y compilar la aplicación móvil en tu equipo sin errores de dependencias o del compilador.

---

## 1. Requisitos Previos

Antes de configurar el proyecto, asegúrate de tener instaladas las siguientes herramientas:

1. **Git:** [Descargar Git](https://git-scm.com/) (o vía terminal: `winget install --id Git.Git -e --source winget`).
2. **Flutter SDK (Canal Estable 3.24+):** [Descargar Flutter SDK](https://docs.flutter.dev/get-started/install/windows/mobile).
   * Descomprime Flutter en una ruta accesible y sin permisos de administrador (por ejemplo, `C:\src\flutter`).
   * Añade `C:\src\flutter\bin` a la variable de entorno `PATH` de tu sistema.
3. **Android Studio:** [Descargar Android Studio](https://developer.android.com/studio).
   * Abre Android Studio y accede a **Settings** > **Languages & Frameworks** > **Android SDK** > pestaña **SDK Tools**.
   * Marca e instala:
     * **Android SDK Command-line Tools (latest)**
     * **Android SDK Platform-Tools**
     * **Android SDK Build-Tools**
4. **Editor:** Visual Studio Code con las extensiones oficiales **Flutter** y **Dart** instaladas.

---

## 2. Puesta en Marcha del Proyecto

### Paso 1: Clonar el repositorio
Abre una terminal (PowerShell o Git Bash) y descarga el proyecto:
```bash
git clone <URL_DEL_REPOSITORIO>
cd zeroinfra

```

### Paso 2: Descargar dependencias

Instala los paquetes de Flutter declarados en `pubspec.yaml` (`flutter_blue_plus`, `protobuf`, `flutter_map`, etc.):

```bash
flutter pub get

```

### Paso 3: Instalar el NDK de Android (OBLIGATORIO)

El compilador Gradle requiere la versión específica **`28.2.13676358`** del NDK de Android. Si no se encuentra instalada en el disco local, la compilación fallará arrojando el error `Package ndk not found`.

* **Opción A (Recomendada - PowerShell):**
Ejecuta la siguiente orden en PowerShell para descargar e instalar automáticamente la versión exacta:
```powershell
$sdkManager = (Get-ChildItem -Path "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools" -Filter "sdkmanager.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
& $sdkManager --install "ndk;28.2.13676358"

```


*(Si el instalador solicita confirmación en la consola, introduce `y` y pulsa Enter).*
* **Opción B (Manual - Android Studio):**
1. Ve a **Tools** > **SDK Manager** (o *Settings > Languages & Frameworks > Android SDK*).
2. Haz clic en la pestaña **SDK Tools**.
3. En la esquina inferior derecha, marca la casilla **Show Package Details**.
4. Despliega **NDK (Side by side)**, marca la casilla de la versión **`28.2.13676358`** y haz clic en **Apply**.



### Paso 4: Validar licencias y estado del entorno

Comprueba que el entorno de desarrollo esté listo y sin advertencias bloqueantes:

```bash
flutter doctor --android-licenses
flutter doctor

```

*(Verifica que tanto **Flutter** como **Android toolchain** muestren el indicador verde `[✓]`).*

---

## 3. Modos de Ejecución

### Opción A: En un dispositivo Android físico (Recomendado para pruebas LoRa / BLE)

1. En tu móvil Android, abre **Ajustes** > **Información del teléfono** y pulsa 7 veces sobre **Número de compilación** para habilitar las opciones de desarrollo.
2. Entra en **Ajustes** > **Opciones de desarrollador** y activa **Depuración por USB**.
3. Activa la **Ubicación (GPS)** en el móvil *(en Android es indispensable para que el escaneo Bluetooth BLE detecte balizas cercanas)*.
4. Conecta el móvil al ordenador mediante cable USB, acepta la depuración en la pantalla del dispositivo y verifica que el sistema lo reconoce:
```bash
flutter devices

```


5. Inicia la app:
```bash
flutter run

```



### Opción B: En Emulador Android (Para pruebas visuales de interfaz)

1. Abre **Android Studio** y arranca un dispositivo virtual desde el **Device Manager**.
2. Con el emulador activo en pantalla, ejecuta:
```bash
flutter run

```



*(Nota: Los emuladores de PC no emulan antenas Bluetooth físicas, por lo que no pueden establecer conexión real con las placas ESP32).*

### Opción C: En Windows Desktop (Maquetación rápida de pantallas)

Para modificar interfaces y ver los cambios al instante sin necesidad de emuladores pesados:

```bash
flutter run -d windows

```

---

## 4. Solución de Problemas Frecuentes

* **`Package ndk not found` o fallo en `assembleDebug`:**
Revisa el **Paso 3**. Comprueba que la carpeta `ndk\28.2.13676358` exista en `%LOCALAPPDATA%\Android\Sdk\`.
* **El comando `flutter` no se reconoce:**
Asegúrate de haber añadido la carpeta `flutter\bin` al `PATH` de las variables de entorno de tu usuario y reinicia la terminal.
* **La app no detecta placas Meshtastic por Bluetooth:**
Verifica que el móvil físico tenga activos tanto el Bluetooth como el GPS, y que se hayan aceptado los permisos de "Dispositivos cercanos" al iniciar la app.

---

## 5. Flujo de Trabajo en Git

1. Crea siempre una rama propia antes de comenzar una tarea:
```bash
git checkout -b feature/nombre-de-la-tarea

```


2. Antes de subir cambios, valida que el código compila sin errores estáticos:
```bash
flutter analyze

```


3. Envía tus cambios al repositorio remoto:
```bash
git push origin feature/nombre-de-la-tarea
```
