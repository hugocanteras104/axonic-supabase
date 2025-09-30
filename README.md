# Axonic Assistant 🚀

**Axonic Assistant** es un agente conversacional proactivo creado por **Axonic Dynamics**.  
No es “otro chatbot”: es un **empleado virtual** que opera nativamente en **WhatsApp**,  
capaz de gestionar tanto la relación con clientes como la operación interna del negocio.

---

## 🌐 Visión

- **Modo DUAL**: distingue entre mensajes del **propietario** y de **clientes/leads**, aplicando lógicas diferentes en cada caso.  
- **Agente proactivo**: no espera a que se le pregunte; detecta oportunidades (cancelaciones, cross-sell, follow-ups) y actúa.  
- **Unificación de canal**: el dueño gestiona su negocio y los clientes reservan servicios desde el mismo chat.  

---

## 🏗️ Arquitectura Técnica

| Capa                 | Tecnología                        | Rol |
|----------------------|-----------------------------------|-----|
| Canal Conversacional | WhatsApp Business Cloud API       | Mensajes (texto, audio, botones, plantillas) |
| Orquestador          | **n8n** (self-hosted en VPS)      | Flujos, integraciones y enrutamiento |
| Base de Datos        | **Supabase** (Postgres + RLS)     | Usuarios, citas, inventario, knowledge base |
| Motor IA             | **Google Gemini 2.5 Pro**         | Comprensión de lenguaje natural, generación de respuestas y planes de acción |
| Agenda               | Google Calendar API               | Disponibilidad y confirmación en tiempo real |
| Infraestructura      | VPS + Docker + Caddy (SSL)        | Hosting, seguridad y monitoreo |

---

## 🧩 Modelo de Datos (Supabase)

- **profiles**: usuarios y roles (`owner`, `lead`)  
- **appointments**: citas vinculadas a Google Calendar  
- **services**: catálogo de tratamientos  
- **inventory**: productos, stock y precios  
- **knowledge_base**: FAQs y contenido dinámico  
- **cross_sell_rules**: reglas de venta cruzada  
- **waitlists**: lista de espera para reubicar cancelaciones  
- **audit_logs**: seguridad y trazabilidad  

---

## ⚙️ Flujos Clave (n8n)

- **Webhook WhatsApp → Router DUAL** (cliente vs propietario)  
- **Modo Asistente (cliente)**: reservas, FAQs, asesor de belleza IA, recordatorios  
- **Modo Comandante (dueño)**: gestión de agenda, stock, informes, knowledge base  
- **Optimizador Tetris**: relleno automático de huecos por cancelaciones  
- **Cross-selling inteligente**: sugerencias contextuales en tiempo real  

---

## 🎯 Funcionalidades

### Para Clientes
- Reservas instantáneas vía WhatsApp.  
- Recomendaciones personalizadas de tratamientos.  
- Recordatorios automáticos y seguimiento post-visita.  
- Soporte a voz/notas de audio.  

### Para Dueños
- Consultar agenda, ventas o stock con lenguaje natural.  
- Mover/cancelar citas directamente desde WhatsApp.  
- Recibir informes diarios de negocio.  
- Automatización de campañas y upselling.  

---

## 🆚 Diferenciación frente a la competencia

| Competidor      | Enfoque | Limitación principal |
|-----------------|---------|---------------------|
| Hubtype         | Enterprise CX | No cubre operativa interna ni modo dueño |
| Landbot         | No-code SMB   | Requiere configurar todo manualmente |
| WATI            | SMB WhatsApp  | Sin proactividad real ni verticalización |
| Bewe            | Suite belleza  | Panel web, no WhatsApp nativo |
| Podium/Birdeye  | SMB USA       | Foco en SMS, no optimizados para WhatsApp |

👉 **Axonic Assistant = gestión integral + proactividad + WhatsApp nativo.**

---

## 📈 Métricas y KPIs

- Conversión WhatsApp → citas  
- Reducción de cancelaciones  
- Incremento en ventas por cross-sell  
- Tiempo medio de respuesta < 2s  
- Uptime y latencia monitorizados  

---

## 🗺️ Roadmap

- **Fase 1 (MVP)** – Arquitectura dual, reservas, inventario y FAQs ✅  
- **Fase 2** – Marketing automatizado, predicción de demanda, dashboard web  
- **Fase 3** – SaaS multi-tenant, integraciones marketplace, IA predictiva avanzada  

---

## 🔒 Seguridad

- Cumplimiento **GDPR**  
- Roles seguros con **RLS en Supabase**  
- Tokens y credenciales en Vault  
- Auditoría completa de acciones críticas  

---

## ✨ Lema

**“Un único número de WhatsApp para hablar con tus clientes y con tu negocio.”**

---
