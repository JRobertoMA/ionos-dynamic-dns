# Script de DNS para IONOS IPv6 en Self-hosted

Este script automatiza la actualización de registros DNS de tipo `AAAA` (IPv6) en IONOS. Está diseñado para ejecutarse periódicamente en un servidor o dispositivo cuya dirección IPv6 pública puede cambiar, asegurando que tus subdominios siempre apunten a la IP correcta.

## Características Principales

- **Actualización Automática de IPv6**: Mantiene los registros `AAAA` sincronizados con la IP pública del host.
- **Manejo Seguro de Credenciales**: Utiliza variables de entorno para las claves de API, evitando exponerlas en el código.
- **Eficiencia de API**: Realiza una comprobación local de la IP y solo contacta a la API de IONOS si la IP ha cambiado, evitando llamadas innecesarias.
- **Notificaciones por Telegram**: Envía alertas sobre cambios de IP y el resultado de las actualizaciones.
- **Sin dependencias complejas**: Solo requiere herramientas comunes de línea de comandos como `curl`, `jq` y `python3`.

---

## 1. Prerrequisitos

Asegúrate de tener las siguientes herramientas instaladas en tu sistema. En la mayoría de las distribuciones de Linux (Debian, Ubuntu, etc.), puedes instalarlas con:

```bash
sudo apt-get update && sudo apt-get install -y curl jq python3
```

- `curl`: Para realizar las peticiones a la API.
- `jq`: Para procesar las respuestas JSON de la API.
- `python3`: Para normalizar las direcciones IPv6 y asegurar una comparación correcta.

---

## 2. Configuración

Sigue estos pasos para configurar el script correctamente.

### 2.1. Clave de la API de IONOS

El script necesita una clave de API para autenticarse con IONOS.

1.  Genera tu clave en el panel de IONOS: **Menú > Servidores & Cloud > API**.
2.  Guarda la clave de forma segura como una variable de entorno. Añade la siguiente línea a tu archivo de perfil de shell (`~/.bashrc` o `~/.zshrc`):

    ```bash
    export IONOS_API_KEY="tu.clave.publica.tu_clave_secreta"
    ```
3.  Recarga tu perfil para aplicar los cambios: `source ~/.bashrc`

### 2.2. Notificaciones de Telegram (Opcional pero recomendado)

Para recibir notificaciones, necesitas un bot de Telegram y tu ID de chat.

1.  **Crear un Bot**:
    - Habla con `@BotFather` en Telegram.
    - Envía `/newbot` y sigue las instrucciones para darle un nombre y un usuario.
    - **Guarda el Token de API** que te proporcionará.

2.  **Obtener tu Chat ID**:
    - Busca a tu bot recién creado y envíale un mensaje (ej. `/start`).
    - Ahora, habla con `@userinfobot` y te mostrará tu **ID de chat**.

3.  **Configurar las Variables de Entorno**:
    - Añade las siguientes líneas a tu `~/.bashrc` o `~/.zshrc`:

    ```bash
    export TELEGRAM_BOT_TOKEN="el_token_de_tu_bot"
    export TELEGRAM_CHAT_ID="tu_id_de_chat"
    ```
    - Recarga tu perfil de nuevo: `source ~/.bashrc`

### 2.3. Configurar el Script (`ionos_dynamic_dns.sh`)

Abre el archivo `ionos_dynamic_dns.sh` y edita la siguiente sección para que coincida con tu configuración:

```shellscript
# Arreglo fijo con los nombres completos de los registros a buscar.
RECORDS_TO_FIND=(
  "sub1.dominio.com"
  "sub2.dominio.com"
  # "otro.dominio.com"
)
```

Añade o elimina los nombres de dominio completos de los registros `AAAA` que deseas que el script gestione.

---

## 3. Instalación y Uso

### 3.1. Dar Permisos de Ejecución

Navega al directorio donde guardaste el script y hazlo ejecutable:

```bash
chmod +x ionos_dynamic_dns.sh
```

### 3.2. Ejecución Manual

Para probar el script, ejecútalo desde la terminal, pasándole como argumento el nombre de tu zona DNS principal:

```bash
./ionos_dynamic_dns.sh dominio.com
```

La primera vez, debería detectar el cambio de IP (de "ninguna registrada" a la actual) y actualizar los registros. Las siguientes ejecuciones, si la IP no ha cambiado, terminarán rápidamente sin contactar a la API.

---

## 4. Automatización con Cron

Para que el script se ejecute automáticamente, puedes añadirlo a `cron`.

1.  Abre el editor de cron:
    ```bash
    crontab -e
    ```
2.  Añade la siguiente línea al final del archivo para ejecutar el script cada 10 minutos:

    ```crontab
    */10 * * * * ${HOME}/ionos_dynamic_dns.sh dominio.com >> ${HOME}/ionos_dns_ipv6.log 2>&1
    ```

    **Desglose del comando:**
    - `*/10 * * * *`: Ejecuta el comando cada 10 minutos.
    - `${HOME}/ionos_dynamic_dns.sh dominio.com`: La ruta absoluta al script y el argumento requerido. **Asegúrate de que la ruta sea correcta.**
    - `>> ${HOME}/ionos_dns_ipv6.log 2>&1`: Redirige toda la salida (tanto la estándar como los errores) a un archivo de log. Esto es útil para depurar problemas sin recibir correos de `cron`.
