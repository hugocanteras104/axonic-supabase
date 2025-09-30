# Axonic Assistant – Supabase DB

Este repositorio contiene las **migraciones SQL** y **datos de prueba** que definen la base de datos de Axonic Assistant.  
El proyecto está organizado para que sea fácil de mantener, entender y extender, tanto por humanos como por herramientas de IA (Codex, Copilot, etc.).

---

## 🎯 Intención del proyecto
- Proveer un esquema de base de datos **versionado** y **idempotente**.
- Dar soporte al **Modo DUAL** de Axonic Assistant:
  - **Owner (dueño/gestor)**: acceso completo a gestión y métricas.
  - **Lead/Cliente**: acceso limitado a citas, promociones y conocimiento.
- Facilitar el **debugging** y la navegación en entornos remotos (Supabase web).

---

## 📂 Estructura de migraciones
supabase/
migrations/
0001_extensions_enums.sql -- Extensiones y ENUMs
0002_core_tables.sql -- Tablas principales y de recursos
0003_indexes_constraints_views.sql -- Índices, constraints y vistas de métricas
0004_functions_triggers.sql -- Funciones genéricas y triggers
0005_feature_kb_search.sql -- Knowledge Base (normalización, búsqueda híbrida, tracking)
0006_policies_rls_grants.sql -- Políticas RLS y permisos
0099_seed_dev.sql -- Seeds de desarrollo (datos inventados)

yaml
Copiar código

---

## ⚙️ Uso en Supabase (web)
1. Abre tu [proyecto en Supabase](https://supabase.com/dashboard).  
2. Ve a la pestaña **SQL Editor**.  
3. Copia el contenido de cada archivo en orden (`0001`, `0002`, … `0099`) y ejecútalo.  
   - Si ya tenías tablas, las migraciones son **idempotentes**, no fallarán.  
   - `0099_seed_dev.sql` es **solo para desarrollo** (datos inventados).  
4. Verifica en la pestaña **Table editor** que las tablas y vistas se han creado correctamente.

---

## ⚠️ Notas importantes
- `0099_seed_dev.sql` contiene **datos de ejemplo** para pruebas.  
  **No lo uses en producción**.  
- Las migraciones están diseñadas para ser **idempotentes**:  
  puedes ejecutarlas varias veces sin que fallen.  
- La Knowledge Base incluye:
  - **Normalización de texto** (`norm_txt`).  
  - **Búsqueda híbrida** (similaridad + keywords).  
  - **Tracking de popularidad** con rate-limit por usuario.

---

## 📈 Roadmap DB
- Añadir más vistas de métricas para el **Owner Dashboard**.  
- Ampliar políticas RLS para escenarios multi-clínica.  
- Integrar logs más detallados en `audit_logs`.  
- Extender seeds con escenarios realistas para demo.  

---

## 👥 Contribución
- Mantén la convención de nombres: `000X_descripcion.sql`.  
- Usa commits descriptivos:  
  - `feat(db):` para nuevas tablas o funciones.  
  - `fix(db):` para correcciones.  
  - `chore(db):` para seeds o tareas menores.  
- Si añades seeds nuevos, hazlo siempre en un archivo `0099_...`.

---

## 📝 Licencia
Este repositorio es de uso interno para el proyecto **Axonic Assistant**.  
