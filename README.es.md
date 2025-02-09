# Proof of Capital

**Disponible en otros idiomas:** [Русский](README.ru.md) | [English](README.md)

---

Proof of Capital es una tecnología de creación de mercado inteligente (smart contract) que protege los intereses de todos los poseedores. Los creadores transfieren toda la emisión libre de su activo al contrato, y las monedas se liberan solo por TON, que permanece en el contrato como garantía. El contrato puede tanto vender monedas, recibiendo garantía de los niveles superiores, como aceptar la devolución de monedas para liberar garantía de los niveles inferiores, aumentando así el precio mínimo del activo.

---

## Contenido

- [Estructura del Proyecto - Blueprint](#estructura-del-proyecto---blueprint)
- [Ejecución del Contrato](#ejecución-del-contrato)
  - [Agregar un Nuevo Contrato](#agregar-un-nuevo-contrato)
  - [Construcción](#construcción)
  - [Pruebas](#pruebas)
  - [Despliegue o Ejecución de un Script](#despliegue-o-ejecución-de-un-script)
- [Disposiciones Principales](#disposiciones-principales)
  - [Variables Definidas Durante la Inicialización y Despliegue del Contrato](#variables-definidas-durante-la-inicialización-y-despliegue-del-contrato)
  - [Descripción de las Variables](#descripción-de-las-variables)
- [Principio de Funcionamiento del Contrato](#principio-de-funcionamiento-del-contrato)
  - [Funciones del Contrato](#funciones-del-contrato)
  - [Notas Importantes](#notas-importantes)
- [Acceso a las Funciones Getter](#acceso-a-las-funciones-getter)
- [Información de Contacto](#información-de-contacto)

---

## Estructura del Proyecto - Blueprint

- `contracts` — código fuente de todos los smart contracts del proyecto y sus dependencias.
- `wrappers` — wrappers (clases que implementan `Contract` de ton-core) para contratos, incluyendo primitivas para [de]serialización y funciones de compilación.
- `tests` — pruebas para contratos.
- `scripts` — scripts utilizados en el proyecto, principalmente para despliegue.

## Ejecución del Contrato

### Agregar un Nuevo Contrato

```bash
npx blueprint create ContractName
# o
yarn create ton ContractName
```

Al crear, seleccione `An empty contract (TACT)`.

### Construcción

```bash
npx blueprint build
# o
yarn blueprint build
```

### Pruebas

```bash
npx blueprint test
# o
yarn blueprint test
```

### Despliegue o Ejecución de un Script

```bash
npx blueprint run
# o
yarn blueprint run
```

---

## Disposiciones Principales

### Variables Definidas Durante la Inicialización y Despliegue del Contrato

Durante la inicialización y despliegue del contrato en Tact, se establecen las siguientes variables, que definen las configuraciones principales del contrato y su estado inicial:

### Descripción de las Variables

| Variable                               | Tipo de Datos     | Descripción                                                          |
|----------------------------------------|-------------------|----------------------------------------------------------------------|
| **owner**                              | `Address`         | Dirección del propietario del contrato.                              |
| **marketMakerAddress**                 | `Address`         | Dirección del creador de mercado.                                    |
| **jettonMasterAddress**                | `Address`         | Dirección del contrato maestro de jetton.                            |
| **returnWalletAddress**                | `Address`         | Dirección de la billetera para devoluciones.                         |
| **royaltyWalletAddress**               | `Address`         | Dirección de la billetera de regalías.                               |
| **lockEndTime**                        | `Int as uint64`   | Tiempo de finalización del bloqueo (en segundos desde la época UNIX).|
| **initialPricePerToken**               | `Int as coins`    | Precio inicial por jetton.                                           |
| **firstLevelJettonQuantity**           | `Int as coins`    | Cantidad de jettons en el primer nivel.                              |
| **priceIncrementMultiplier**           | `Int as uint16`   | Multiplicador para aumentar el precio por jetton.                    |
| **levelIncreaseMultiplier**            | `Int as uint16`   | Multiplicador para aumentar el nivel.                                |
| **trendChangeStep**                    | `Int as uint8`    | Paso para el cambio de tendencia.                                    |
| **levelDecreaseMultiplierafterTrend**  | `Int as uint16`   | Multiplicador para disminuir el nivel después del cambio de tendencia.|
| **profitPercentage**                   | `Int as uint16`   | Porcentaje de beneficio.                                             |

---

## Principio de Funcionamiento del Contrato

El contrato Proof of Capital está diseñado para gestionar la emisión de jettons respaldados por capital, con condiciones transparentes para la emisión y recompra.

### Funciones del Contrato

1. **Despliegue y Configuración Inicial:**
   - Después de desplegar el contrato, el creador lo recarga con jettons y establece un bloqueo por **seis meses** o **10 minutos** (para pruebas iniciales del contrato).
   - El creador puede extender el **bloqueo** por un período adicional: **seis meses** o **10 minutos**.

2. **Interacción con el Contrato:**
   - **Creador de Mercado (Market Maker):**
     - Durante el período de bloqueo, solo el creador de mercado puede intercambiar tokens con el contrato.
     - Tiene el derecho de comprar y vender jettons, equilibrando el precio en el contrato con los precios en los pools en DEX.
   - **Otros Usuarios:**
     - **Dos meses antes del final del bloqueo**, todos los usuarios pueden interactuar con el contrato.
     - Pueden devolver los jettons comprados al contrato a cambio de garantía.
   - **Return Wallet:**
     - Una billetera especial desde la cual se devuelven tokens al contrato, liberando garantía de los niveles inferiores.
     - Esta es una alternativa al procedimiento de quema, con el objetivo de utilizar los tokens ganados en el futuro a medida que crece la capitalización.

3. **Expiración del Bloqueo:**
   - Después de que finaliza el período de bloqueo, el creador puede retirar todas las monedas y todo el TON del contrato.

### Notas Importantes

- **Use las Funciones Getter:**
  - Al trabajar con el contrato, siempre use las funciones getter para verificar los resultados de sus operaciones **antes** de ejecutarlas.
  - Esto ayudará a evitar resultados inesperados.

- **Interacción con el Contrato:**
  - **Nunca envíe monedas (tokens) directamente desde su billetera al contrato.**
    - Si envía tokens sin llamar a las funciones correspondientes, el contrato puede no procesar la transacción y sus monedas se perderán.
  - Si envía TON directamente:
    - El contrato puede rechazar la operación si faltan más de dos meses para el final del bloqueo.
    - El contrato puede enviarle monedas (jettons) si faltan menos de dos meses para el final del bloqueo.
    - **Asegúrese de verificar los resultados de las funciones getter antes de interactuar con el contrato.** Si el contrato no tiene suficientes jettons, le enviará todo lo que le queda. Si no quedan monedas, el TON simplemente irá al balance del contrato.

- **Características de la Venta de Remanentes de Jetton:**
  - Si intenta devolver más jettons de los que el contrato debe recomprar, el pago será todo el saldo restante de TON reservado para recomprar monedas, y las monedas excedentes irán al balance del contrato.
  - **Asegúrese de estudiar la salida de la función getter `jetton_available` antes de enviar jettons al contrato.**

- **Beneficios y Comisiones:**
  - El **20%** de las ganancias se dirige a la billetera de **Regalías (Royalty)** especificada en el sitio web [proofofcapital.org](https://proofofcapital.org).
  - El **80%** se envía a la billetera del creador como fondo para desarrollo y marketing.

---

## Acceso a las Funciones Getter

Para obtener datos sobre el estado actual del contrato y los resultados de funciones internas, puede utilizar las funciones getter:

1. Vaya a **TON Viewer** o una herramienta similar.
2. Abra la pestaña **Methods**.
3. En el campo **Arbitrary method**, ingrese el nombre de la función getter.
4. Si es necesario, agregue argumentos.
5. Haga clic en el botón **Execute** para realizar la solicitud.

**Recomendamos** siempre usar las funciones getter antes de realizar operaciones para verificar los resultados esperados.

---

## Información de Contacto

Para cualquier pregunta, contáctenos a través de los datos de contacto enumerados en el sitio web [proofofcapital.org](https://proofofcapital.org).

Hemos pasado la segunda auditoría, que se publicará para la versión actual del contrato. Actualmente estamos preparando el lanzamiento de la próxima versión, que tendrá en cuenta todas las recomendaciones de los auditores. Un ejemplo que opera en esta versión del contrato está disponible [en este enlace](https://tonviewer.com/EQBGN2w9fUVNfJ0IBKDQ2vVy6S_lDug4q1UYdRhkFA-r_POK).

---

**¡Atención!** Enviar monedas directamente al contrato y realizar transacciones sin un análisis previo de la salida de las funciones getter puede conducir a la pérdida de fondos. Siempre verifique la dirección y utilice los métodos proporcionados para interactuar con el contrato.