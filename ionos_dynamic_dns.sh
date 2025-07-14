#!/bin/bash

# ionos_dynamic_dns.sh
#
# Este script obtiene el ID de una zona DNS de IONOS filtrando por su nombre.
#
# Dependencias: curl, jq

# --- Configuración IONOS API ---
if [[ -z "${IONOS_API_KEY}" ]]; then
  echo "❌ Error: La variable de entorno IONOS_API_KEY no está definida."
  echo "   Para definirla, ejecute:"
  echo "   export IONOS_API_KEY='su_api_key_aqui'"
  exit 1
fi

# (Opcional) Configuración para notificaciones de Telegram.
if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" ]]; then
  echo "ℹ️  Info: No se han definido las variables de entorno para Telegram (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID). No se enviarán notificaciones."
  # No salimos, el script puede funcionar sin notificaciones.
else
  # Variable para habilitar las notificaciones
  NOTIFICATIONS_ENABLED=true
fi

# Verifica si se proporcionó el dominio principal como argumento.
if [ -z "$1" ]; then
  echo "❌ Error: Debes proporcionar el nombre de la zona principal como argumento."
  echo "Uso: $0 <zona_principal.com>"
  exit 1
fi
MAIN_ZONE_NAME="$1"

# Arreglo fijo con los nombres completos de los registros a buscar.
RECORDS_TO_FIND=(
  "sub1.dominio.com"
  "sub2.dominio.com"
)

# Archivo para guardar la última IP conocida y evitar llamadas innecesarias a la API.
# Se guardará en el directorio home del usuario que ejecuta el script.
LAST_IP_FILE="${HOME}/.ionos_dns_last_ipv6.txt"
# ---------------------

# --- Funciones Auxiliares ---
# Función para expandir una dirección IPv6 a su formato completo (canónico).
# Ejemplo: ::1 -> 0000:0000:0000:0000:0000:0000:0000:0001
# Dependencia: python3
normalize_ipv6() {
  local ip_addr="$1"
  # Si python3 no está disponible, devuelve la IP original para mantener la compatibilidad.
  if ! command -v python3 &> /dev/null; then
    echo "$ip_addr"
    return
  fi
  # Usa la librería 'ipaddress' de Python para una conversión robusta.
  # Si falla (p.ej. no es una IP válida), devuelve la original.
  python3 -c "import ipaddress; print(ipaddress.IPv6Address('$ip_addr').exploded)" 2>/dev/null || echo "$ip_addr"
}

# Función para enviar una notificación a través de Telegram
send_telegram_notification() {
  # Solo envía si las notificaciones están habilitadas.
  if [[ "$NOTIFICATIONS_ENABLED" != "true" ]]; then
    return
  fi

  local message_text="$1"
  # Usamos printf para construir el JSON de forma segura y escapando caracteres
  local json_payload
  json_payload=$(printf '{"chat_id": "%s", "text": "%s", "parse_mode": "Markdown"}' "$TELEGRAM_CHAT_ID" "$message_text")

  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -H 'Content-Type: application/json' \
    -d "$json_payload" > /dev/null
}

# Función para actualizar un registro DNS a través de la API de IONOS.
update_dns_record() {
  local zone_id="$1"
  local record_id="$2"
  local new_ip="$3"
  local record_name="$4" # Se añade para usar en las notificaciones

  echo "     -> Intentando actualizar la IP a: ${new_ip}"

  # Construye el cuerpo (payload) del JSON para la petición PUT.
  # Usamos printf para insertar de forma segura la IP en la cadena JSON.
  local update_payload
  update_payload=$(printf '{"content": "%s", "ttl": 3600, "prio": 0, "disabled": false}' "$new_ip")

  # Realiza la llamada a la API con el método PUT para actualizar.
  # -w "%{http_code}" escribe el código de estado HTTP a la salida estándar.
  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "https://api.hosting.ionos.com/dns/v1/zones/${zone_id}/records/${record_id}" \
    -H "accept: application/json" \
    -H "X-API-Key: ${IONOS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$update_payload")

  # Comprueba si la actualización fue exitosa (códigos HTTP 2xx).
  if [[ "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
    echo "     -> ✅ Actualización exitosa (HTTP ${http_status})."
    send_telegram_notification "✅ *Éxito*: La IP para \`${record_name}\` se actualizó a \`${new_ip}\`."
    return 0 # Retorna 0 en caso de éxito
  else
    echo "     -> ❌ Falló la actualización (HTTP ${http_status})."
    send_telegram_notification "❌ *Fallo*: No se pudo actualizar la IP para \`${record_name}\`. (HTTP ${http_status})"
    return 1 # Retorna 1 en caso de fallo
  fi
}

echo "Paso 1: Obteniendo la dirección IPv6 global del host..."
HOST_IPV6=$(curl -s -6 ifconfig.co)

if [[ -z "$HOST_IPV6" ]]; then
    echo "❌ Error: No se pudo obtener la dirección IPv6 global del host. Saliendo."
    exit 1
fi
echo "✅ IPv6 global del host encontrada: ${HOST_IPV6}"

# --- Comprobación de IP local para evitar llamadas innecesarias ---
LAST_KNOWN_IP=""
if [ -f "$LAST_IP_FILE" ]; then
  LAST_KNOWN_IP=$(cat "$LAST_IP_FILE")
fi

if [[ "$(normalize_ipv6 "$HOST_IPV6")" == "$(normalize_ipv6 "$LAST_KNOWN_IP")" ]]; then
  echo "✅ La IP del host (${HOST_IPV6}) no ha cambiado desde la última comprobación. No se requiere ninguna acción."
  send_telegram_notification "✅ La IP del host \`${HOSTNAME}\` no ha cambiado desde la última comprobación. No se requiere ninguna acción."
  exit 0
fi

echo "IP ha cambiado de '${LAST_KNOWN_IP:-ninguna registrada}' a '${HOST_IPV6}'. Procediendo a actualizar DNS..."
send_telegram_notification "ℹ️ *Cambio de IP detectado* a \`${HOST_IPV6}\`. Iniciando actualización de DNS..."
echo
echo "Paso 2: Buscando el ID para la zona: ${MAIN_ZONE_NAME}..."

# Realiza la llamada a la API para obtener todas las zonas.
ALL_ZONES_JSON=$(curl -s -X 'GET' \
  'https://api.hosting.ionos.com/dns/v1/zones' \
  -H 'accept: application/json' \
  -H "X-API-Key: ${IONOS_API_KEY}")

# Busca el ID de la zona principal.
ZONE_ID=$(echo "$ALL_ZONES_JSON" | jq -r --arg domain_name "$MAIN_ZONE_NAME" '.[] | select(.name == $domain_name) | .id')

if [[ -z "$ZONE_ID" ]]; then
  echo "❌ Error: No se pudo encontrar una zona con el nombre '${MAIN_ZONE_NAME}'."
  exit 1
fi
echo "✅ Zona encontrada. ID: ${ZONE_ID}"
echo
echo "Paso 3: Obteniendo todos los registros para la zona ${MAIN_ZONE_NAME}..."
# Usa el ZONE_ID para obtener los registros de esa zona específica.
# Nota: Las variables dentro de comillas simples (') no se expanden. Se deben usar comillas dobles (").
ZONE_RECORDS_JSON=$(curl -s -X 'GET' \
  "https://api.hosting.ionos.com/dns/v1/zones/${ZONE_ID}" \
  -H 'accept: application/json' \
  -H "X-API-Key: ${IONOS_API_KEY}")

# Extrae solo el array de registros para facilitar la búsqueda.
RECORDS_ARRAY_JSON=$(echo "$ZONE_RECORDS_JSON" | jq '.records')

echo
echo "Paso 4: Buscando y comparando datos de registros..."
# Itera sobre el arreglo fijo de registros.

needs_update=false
all_updates_successful=true

for RECORD_NAME in "${RECORDS_TO_FIND[@]}"; do
  # Busca el ID y el contenido (la IP) del registro.
  # jq devuelve una línea con ID y contenido, filtrando por nombre Y tipo de registro (AAAA).
  read -r RECORD_ID RECORD_CONTENT <<< "$(echo "$RECORDS_ARRAY_JSON" | jq -r --arg record_name "$RECORD_NAME" '.[] | select(.name == $record_name and .type == "AAAA") | "\(.id) \(.content)"')"

  echo "----------------------------------------------------"
  if [[ -n "$RECORD_ID" ]]; then
    echo "✅ Registro AAAA: ${RECORD_NAME}"
    echo "   - ID en DNS:      ${RECORD_ID}"
    echo "   - IP en DNS:      ${RECORD_CONTENT}"

    # Compara con la IP del host solo si se pudo obtener
    if [[ -n "$HOST_IPV6" ]]; then
        # Normaliza ambas IPs a su formato completo para una comparación fiable.
        NORMALIZED_HOST_IP=$(normalize_ipv6 "$HOST_IPV6")
        NORMALIZED_RECORD_IP=$(normalize_ipv6 "$RECORD_CONTENT")

        if [[ "$NORMALIZED_HOST_IP" == "$NORMALIZED_RECORD_IP" ]]; then
            echo "   - Estado:         👍 Coincide con la IP del host."
        else
            echo "   - Estado:         ❗️ NO COINCIDE. Se requiere actualización."
            # Si la función de actualización falla (retorna un código distinto de 0),
            # marcamos que no todas las actualizaciones fueron exitosas.
            if ! update_dns_record "$ZONE_ID" "$RECORD_ID" "$HOST_IPV6" "$RECORD_NAME"; then
                all_updates_successful=false
            fi
        fi
    fi
  else
    echo "⚠️  Registro AAAA: ${RECORD_NAME} -> No se encontró."
  fi
done

# Paso 5: Guardar la nueva IP localmente si todas las actualizaciones fueron exitosas.
if [[ "$all_updates_successful" == "true" ]]; then
  echo
  echo "✅ Todas las actualizaciones de DNS fueron exitosas. Guardando la nueva IP en el archivo local."
  send_telegram_notification "✅ *Proceso finalizado*. Todas las actualizaciones fueron exitosas."
  echo "$HOST_IPV6" > "$LAST_IP_FILE"
else
  echo
  echo "❌ Ocurrieron errores durante la actualización de DNS. No se guardará la nueva IP para reintentar en la próxima ejecución."
  send_telegram_notification "❌ *Proceso finalizado con errores*. Revisa los logs del servidor."
  exit 1 # Salir con un código de error para que cron sepa que algo falló.
fi
