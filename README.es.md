# Prueba de Capital (Proof of Capital)

**Disponible en otros idiomas:** [Русский](README.ru.md) | [English](README.md)

---

La Prueba de Capital (**Proof of Capital**) es una tecnología de creación de mercado inteligente (smart contract) que protege los intereses de todos los poseedores. 

Los creadores transfieren toda la emisión disponible de su activo al contrato, y las monedas solo se liberan a cambio de 
TON u otros tokens compatibles, que permanecen en el contrato como garantía. El contrato permite tanto vender monedas, recibiendo garantía de los niveles superiores, como devolverlas para liberar garantía de los niveles inferiores, aumentando así el precio mínimo del activo.

El contrato admite lanzamientos desde cero y también puede tener en cuenta el historial previo del activo. Para ello se puede fijar un parámetro de compensación, equivalente a las monedas vendidas previamente, que permite comenzar la operación del contrato al nivel de precio y garantía deseados. Esto es especialmente importante para proyectos existentes que migran a Proof of Capital.

---

## Contenido

- [Prueba de Capital (Proof of Capital)](#prueba-de-capital-proof-of-capital)
  - [Contenido](#contenido)
  - [Estructura del proyecto Blueprint](#estructura-del-proyecto-blueprint)
  - [Lanzamiento del contrato](#lanzamiento-del-contrato)
    - [Agregar un nuevo contrato](#agregar-un-nuevo-contrato)
    - [Compilación](#compilación)
    - [Implementación o ejecución del script](#implementación-o-ejecución-del-script)
  - [Puntos principales](#puntos-principales)
    - [Variables definidas durante la inicialización y el despliegue del contrato](#variables-definidas-durante-la-inicialización-y-el-despliegue-del-contrato)
    - [Descripción de las variables](#descripción-de-las-variables)
  - [Principio de funcionamiento del contrato](#principio-de-funcionamiento-del-contrato)
    - [Funciones del contrato](#funciones-del-contrato)
    - [Notas importantes](#notas-importantes)
  - [Acceso a las funciones "getter"](#acceso-a-las-funciones-getter)
  - [Información de contacto](#información-de-contacto)

---

## Estructura del proyecto Blueprint

- `contracts` — código fuente de todos los contratos inteligentes del proyecto y sus dependencias.
- `wrappers` — envoltorios (clases que implementan `Contract` de ton-core) para contratos, incluyendo primitivas para [de]serialización y funciones de compilación.
- `tests` — pruebas para contratos.
- `scripts` — scripts utilizados en el proyecto, principalmente para despliegue.

## Lanzamiento del contrato

### Agregar un nuevo contrato

```bash
npx blueprint create ContractName
# o
yarn create ton ContractName
```
Al crear, selecciona `An empty contract (TACT)`.

### Activar la versión actual del compilador

En el momento de redactar esta instrucción se utiliza la versión 1.6.7.
```bash
npx @tact-lang/compiler@1.6.7
# o
yarn add @tact-lang/compiler@1.6.7
```

### Compilación

```bash
npx blueprint build
# o
yarn blueprint build
```

### Implementación o ejecución del script

```bash
npx blueprint run
# o
yarn blueprint run
```

---

## Puntos principales

### Variables definidas durante la inicialización y el despliegue del contrato

Durante la inicialización y el despliegue del contrato en Tact, se establecen las siguientes variables, que determinan la configuración principal del contrato y su estado inicial:

### Descripción de las variables

| Variable                              | Tipo de dato       | Descripción                                                               |
|---------------------------------------|--------------------|---------------------------------------------------------------------------|
| **owner**                             | `Address`          | Dirección del propietario del contrato.                                   |
| **marketMakerAddress**                | `Address`          | Dirección del creador de mercado.                                         |
| **launchJettonMasterAddress**               | `Address`          | Dirección del contrato maestro del token.                                 |
| **returnWalletAddress**               | `Address`          | Dirección de la billetera de retorno.                                     |
| **royaltyWalletAddress**              | `Address`          | Dirección de la billetera de regalías.                                    |
| **lockEndTime**                       | `Int as uint64`    | Tiempo de fin del bloqueo (en segundos desde la época UNIX).              |
| **initialPricePerToken**              | `Int as coins`     | Precio inicial por token.                                                 |
| **firstLevelJettonQuantity**          | `Int as coins`     | Cantidad de tokens en el primer nivel.                                    |
| **priceIncrementMultiplier**          | `Int as uint16`    | Multiplicador para el incremento del precio por token.                   |
| **levelIncreaseMultiplier**           | `Int as uint16`    | Multiplicador para el incremento de nivel.                                |
| **trendChangeStep**                   | `Int as uint8`     | Paso para el cambio de tendencia.                                         |
| **levelDecreaseMultiplierafterTrend** | `Int as uint16`    | Multiplicador para la disminución de nivel después del cambio de tendencia. |
| **profitPercentage**                  | `Int as uint16`    | Porcentaje de beneficio.                                                  |
| **offsetJettons**                     | `Int as coins`     | Cantidad de tokens vendidos previamente (compensación histórica).         |
| **controlPeriod**                     | `Int as uint32`    | Duración de la "ventana de desbloqueo" en segundos UNIX.                  |
| **jettonSupport**                     | `Bool`             | Activa la compatibilidad para compras de tokens con otros tokens (ej., USDT).  |
| **jettonCollateralMasterAddress**        | `Address`          | Dirección del contrato maestro del token como garantía (si está habilitado). |
| **royaltyProfitPercentage**           | `Int as uint16`    | Porcentaje del beneficio enviado a la billetera de regalías.              |
| **coefficientProfit**           | `Int as uint16`    | Porcentaje de beneficio en los pasos iniciales (hasta que cambie la tendencia)              |
| **jettonDecimals**           | `Int as uint16`    | Cantidad de unidades mínimas en un solo jetón (para los tokens clásicos, 9)              |

---

## Principio de funcionamiento del contrato

El contrato Proof of Capital está diseñado para gestionar la emisión de tokens respaldados por capital, con condiciones transparentes de emisión y recompra.

### Funciones del contrato

1. **Despliegue y configuración inicial:**
   - Tras el despliegue del contrato, el creador lo financia con tokens y establece un bloqueo (**lock**) de **seis meses**, **tres meses** o **10 minutos** (para pruebas iniciales del contrato).
   - El creador puede prolongar el **lock** por un período adicional: **seis meses**, **tres meses** o **10 minutos**.

2. **Interacción con el contrato:**
   - **Creador del Mercado**:
     - Durante el bloqueo y en períodos en los que no está activa la "ventana de desbloqueo", solo el creador de mercado puede intercambiar tokens con el contrato.
     - Tiene derecho a comprar y vender tokens, igualando el precio en el contrato con los precios en los pools de DEX.
   - **Otros usuarios**:
     - **Dos meses antes del fin del bloqueo**, cualquiera puede interactuar con el contrato.
     - Hasta el punto anterior, se puede interactuar con el contrato solo en períodos especiales llamados **"ventana de desbloqueo"**. 
     - Durante la "ventana de desbloqueo" y dos meses antes del fin del bloqueo, cualquiera puede devolver tokens adquiridos al contrato a cambio de la garantía.
   - **Return Wallet**:
     - Billetera especial desde la cual se devuelven tokens al contrato liberando la garantía de los niveles inferiores.
     - Es una alternativa al proceso de destrucción para utilizar tokens ganados en el futuro a medida que crezca la capitalización.

3. **Fin del bloqueo:**
   - Tras el fin del bloqueo, el creador puede retirar todas las monedas y la garantía del contrato.
   
### Notas importantes

- **Usa las funciones getter:**
  - Durante la interacción con el contrato, asegúrate de usar las funciones getter para verificar los resultados de tus operaciones **antes** de ejecutarlas.
  - Esto te ayudará a evitar resultados inesperados.

- **Interacción con el contrato:**
  - Nunca envíes monedas (tokens) directamente desde tu billetera al contrato.
    - Si envías tokens sin llamar a las funciones correspondientes, el contrato puede no procesar la transacción, y tus monedas se perderán.
  - Si envías TON directamente (si se respalda en TON):
    - El contrato puede rechazar la operación si quedan más de dos meses para el fin del bloqueo o si el modo de respaldo en otra moneda está activado.
    - El contrato puede enviarte monedas (tokens) si quedan menos de dos meses para el fin del bloqueo o si ha comenzado una "ventana de desbloqueo".
    - Asegúrate de verificar los resultados de las funciones getter antes de interactuar con el contrato. Si el contrato no tiene suficientes tokens, te enviará todos los que quedan. Si no quedan monedas, los TON simplemente permanecerán en el saldo del contrato.
  - Reglas similares se aplican para el respaldo en otra moneda, sin embargo, dicha interacción se lleva a cabo no directamente, sino a través de herramientas de software especializadas.
    
- **Beneficios y comisiones:**
  - El contrato admite la **configuración dinámica de la distribución de beneficios** entre el propietario (como fondo para desarrollo y marketing) y la billetera de regalías, incluida la posibilidad de cambiar el modo de cobro de beneficios, ya sea por request o inmediatamente.
  - La billetera **Royalty** está indicada en el sitio [proofofcapital.org](https://proofofcapital.org).

---

## Acceso a las funciones "getter"

Para obtener datos sobre el estado actual del contrato y los resultados de las funciones internas, puedes usar las funciones getter:

1. Accede a **TON Viewer** o una herramienta similar.
2. Abre la pestaña **Methods**.
3. En el campo **Arbitrary method**, ingresa el nombre de la función getter.
4. Si es necesario, añade argumentos.
5. Haz clic en el botón **Execute** para realizar la consulta.

**Te recomendamos** siempre utilizar las funciones getter antes de realizar operaciones para verificar los resultados esperados.

---

## Información de contacto

Para cualquier pregunta, contáctanos a través de nuestra información de contacto indicada en el sitio [proofofcapital.org](https://proofofcapital.org).

A principios de febrero realizamos la segunda auditoría, que se publicó en la versión anterior del contrato. Un ejemplo que funciona con la segunda versión del contrato está disponible [enlazando aquí](https://tonviewer.com/EQBGN2w9fUVNfJ0IBKDQ2vVy6S_lDug4q1UYdRhkFA-r_POK).

Ahora hemos lanzado la tercera versión del contrato (la actual) teniendo en cuenta todas las sugerencias de los usuarios y clientes, y también hemos pasado satisfactoriamente una tercera auditoría, que se publicará en la versión actual del contrato.

Mantente al tanto de las noticias importantes y actualizaciones en nuestro canal de Telegram: [@pocorg](https://t.me/pocorg).