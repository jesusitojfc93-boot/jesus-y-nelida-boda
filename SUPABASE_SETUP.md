# Configuración de Supabase

## 1. Crear el proyecto

1. Crea un proyecto en Supabase.
2. Abre **SQL Editor**.
3. Ejecuta todo el contenido de [supabase-schema.sql](supabase-schema.sql).
4. En una base nueva, ejecuta una sola vez [supabase-initial-attendance.sql](supabase-initial-attendance.sql) para cargar los estados históricos iniciales.

En un proyecto existente, vuelve a ejecutar `supabase-schema.sql` para instalar los cambios. No ejecutes el importador histórico si ya tienes respuestas reales. El esquema se puede volver a ejecutar sin reiniciar estados; el importador separado también tiene un marcador de ejecución única.

## 2. Conectar la invitación

En **Project Settings > API**, copia:

- Project URL
- anon public key

Pégalos en [js/supabase-config.js](js/supabase-config.js), reemplazando los valores `TU-PROYECTO` y `TU-CLAVE-ANON`.

La clave `anon` sí puede estar en el frontend. Nunca coloques una `service_role key` en estos archivos.

## 3. Crear el administrador

1. En **Authentication > Users**, crea un usuario con correo y contraseña.
2. En los metadatos de aplicación de ese usuario, establece:

```json
{
  "role": "admin"
}
```

3. Abre [admin.html](admin.html) e inicia sesión con ese usuario.

## 4. Publicar

Sube todos los archivos del proyecto, incluyendo:

- `index.html`
- `admin.html`
- `css/style.css`
- `js/app.js`
- `js/supabase-config.js`
- `supabase-schema.sql`
- `supabase-initial-attendance.sql`

La página pública será la invitación y el panel privado estará en `/admin.html`.

## Qué queda centralizado

- La agenda de invitados.
- La búsqueda de nombres.
- Los nombres corregidos enviados en cada confirmación.
- El acompañante vinculado al invitado principal.
- El bloqueo de invitados ya confirmados.
- Estados pendiente, confirmado y rechazado.
- Edición de nombres desde el panel.
- Exportación de confirmaciones a CSV.
