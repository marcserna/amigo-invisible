# Amigo invisible

Web sencilla para Marc, Ernest, Carla, Noe, Jonay, Oriol, Ivan, Nikola, Aoxin y Cai. Se publica como sitio estático en GitHub Pages; Supabase gestiona las contraseñas y guarda el sorteo y las listas con acceso restringido.

## Preparación

### 1. Crear el proyecto de Supabase

1. Crea un proyecto en [Supabase](https://supabase.com/).
2. En **Authentication → Providers → Email**, deja activo el acceso con contraseña y desactiva el registro público de usuarios.
3. En **Authentication → Users**, crea los diez usuarios. Usa **Auto Confirm User** y asigna una contraseña distinta a cada persona. No hace falta que sean direcciones de correo reales; la web solo las usa como identificadores de acceso:

   | Persona | Email de acceso |
   | --- | --- |
   | Marc | `marc@amigo-invisible.test` |
   | Ernest | `ernest@amigo-invisible.test` |
   | Carla | `carla@amigo-invisible.test` |
   | Noe | `noe@amigo-invisible.test` |
   | Jonay | `jonay@amigo-invisible.test` |
   | Oriol | `oriol@amigo-invisible.test` |
   | Ivan | `ivan@amigo-invisible.test` |
   | Nikola | `nikola@amigo-invisible.test` |
   | Aoxin | `aoxin@amigo-invisible.test` |
   | Cai | `cai@amigo-invisible.test` |

   Apunta las contraseñas y compártelas en privado. Al no ser correos reales, la recuperación de contraseña por email no estará disponible; quien administre el proyecto podrá cambiar una desde Supabase.

### 2. Crear las tablas y hacer el sorteo

1. Abre **SQL Editor → New query** en Supabase.
2. Copia el contenido completo de [`setup.sql`](./setup.sql) y ejecútalo una sola vez, después de crear los diez usuarios.
3. El script crea las tablas y políticas de acceso, registra a los participantes y sortea entre las asignaciones permitidas. Nadie se asigna a sí mismo y cada persona sale una sola vez.
4. No vuelvas a ejecutar el script completo: incluye la creación inicial del sorteo.

Las políticas de seguridad permiten que cada participante vea su propia asignación y las listas de deseos de sí mismo y de su persona asignada. Solo puede añadir o quitar ideas de su propia lista.

### Si ya tienes el sorteo de nueve y vas a añadir a Cai

En este proyecto ya existe el sorteo de nueve. **No vuelvas a ejecutar `setup.sql` ni `add_participants_and_redraw.sql`**. Para añadir a Cai:

1. En **Authentication → Users**, crea la cuenta `cai@amigo-invisible.test`.
2. Abre **SQL Editor → New query** y ejecuta [`add_cai_and_redraw.sql`](./add_cai_and_redraw.sql) una sola vez.
3. La migración conserva las listas de deseos y vuelve a sortear al grupo de diez. Las asignaciones actuales cambiarán.
4. No ejecutes de nuevo esta migración: está protegida para rechazar una segunda ejecución.

Si en el futuro quieres volver a sortear a los diez sin modificar las cuentas ni las listas de deseos, ejecuta [`redraw.sql`](./redraw.sql) en una nueva consulta del SQL Editor. Cada vez que lo ejecutes se cambiarán todas las asignaciones.

Las reglas iniciales son: máximo 15 €, no regalar Funkos ni 30 grapadoras (una roja), mantener el sorteo en secreto y usar las listas de deseos como inspiración. El sorteo evita las parejas Marc-Carla, Ernest-Noe, Ivan-Nikola y Aoxin-Cai en ambos sentidos, y fija Marc → Noe.

### 3. Conectar la web

1. En Supabase, abre **Project Settings → API**.
2. Este proyecto ya tiene en [`config.js`](./config.js) la URL y la clave pública de Supabase. Si configuras otra copia desde cero, copia ahí **Project URL** y la clave pública **anon / publishable** (según la versión del panel).
3. La URL y la clave pública se usan en el navegador; es normal que queden visibles en GitHub. **No pongas nunca la clave `service_role` en la web.** Los datos están protegidos por las políticas RLS de la base de datos.

### 4. Publicar en GitHub Pages

1. Crea un repositorio en GitHub y sube estos archivos a la raíz del branch `main`.
2. En el repositorio, ve a **Settings → Pages**.
3. En **Build and deployment**, elige **Deploy from a branch**, selecciona `main` y la carpeta `/ (root)`, y guarda.
4. Cuando GitHub termine de publicar, comparte el enlace de Pages y la contraseña de cada persona por un canal privado.

## Uso

- Cada persona elige su nombre, introduce su contraseña y ve a quién le ha tocado.
- Cualquiera puede añadir o quitar sus propias ideas; la persona asignada podrá leerlas.
- La asignación no se puede cambiar desde la web.

Las reglas y el diseño se pueden adaptar editando [`index.html`](./index.html) y [`styles.css`](./styles.css).
