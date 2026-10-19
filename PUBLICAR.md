# Publicar RuedaConvert

Hay dos formas de que la gente instale la app, y puedes usar las dos a la vez:

- **Parte A · GitHub (gratis):** el código es público y cualquiera descarga la app desde tu página web. Al abrirla por primera vez, macOS muestra un aviso que hay que aceptar en Ajustes.
- **Parte B · Mac App Store (US$99 al año):** se instala desde la tienda, sin avisos.

---

# Parte A · GitHub (gratis)

- Código: <https://github.com/hebexort771/RuedaConvert>
- Página de descarga: <https://hebexort771.github.io/RuedaConvert/>
- Privacidad: <https://hebexort771.github.io/RuedaConvert/privacidad.html>

El contacto de las páginas es **GitHub Issues** (`/issues` del repositorio), así no publicas tu correo. Si prefieres un correo, agrégalo en `docs/index.html` y `docs/privacidad.html`.

## Publicar una versión nueva

1. Cambia el código y prueba con ⌘R en Xcode.
2. Sube los cambios (GitHub Desktop: resumen → **Commit to main** → **Push origin**).
3. En el repositorio → **Releases → Draft a new release** → **Choose a tag** → escribe la siguiente (`v1.1`, `v1.2`…) → **Create new tag** → **Publish release**.
4. En la pestaña **Actions** un Mac de GitHub compila la app (5 a 10 minutos). Al terminar, `RuedaConvert-macOS.zip` aparece en esa versión y el botón **Descargar para Mac** de la página apunta a ella.

Si en **Actions** aparece una ✕ roja, abre la ejecución, copia el error y pégamelo.

## El aviso de macOS al abrir la app

Quien la descargue verá que macOS "no puede comprobar" la app la primera vez; se abre desde **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente** (está explicado en la página). El aviso desaparece si la app se firma con un certificado *Developer ID* y se notariza con Apple, lo que requiere el Apple Developer Program de la Parte B.

---

# Parte B · Mac App Store

## 0. Lo que necesitas

- **Xcode** (gratis, en la Mac App Store). Pesa bastante; descárgalo con buena conexión.
- **Apple Developer Program**: US$99 al año. Te inscribes en <https://developer.apple.com/programs/enroll/> con tu Apple ID. Apple verifica tu identidad y puede tardar uno o dos días.
  Como te inscribes como persona, en la tienda aparecerá tu nombre legal como vendedor.
- **Dos páginas web públicas**: una de soporte y una de política de privacidad. Apple las exige. Ya están publicadas con la Parte A.

> Puedes hacer los pasos 1 y 2 **antes de pagar** los US$99: Xcode deja probar la app en tu Mac con tu Apple ID normal.

---

## 1. Abrir el proyecto y probarlo en tu Mac

1. Abre **`RuedaConvert.xcodeproj`** (doble clic).
2. En la barra izquierda haz clic en **RuedaConvert** (el icono azul de arriba) → pestaña **Signing & Capabilities**.
3. En **Team** elige tu Apple ID. Si no aparece: *Add an Account…* e inicia sesión.
   Mientras no pagues, saldrá como "Personal Team". Sirve para probar.
4. Pulsa **⌘R** (o el botón ▶︎). La app se abre y muestra la ventana de bienvenida.
5. Prueba todo:
   - Arrastra un PDF desde el Escritorio y, sin soltarlo, pulsa **Shift** → aparece la rueda → suéltalo en **DOCX**.
   - Haz lo mismo con una foto (→ JPG, → TXT) y con un documento de Word (→ PDF).
   - Ve a **Ajustes… → Dar permiso a una carpeta**, elige tu carpeta personal y comprueba que ahora se guarda junto al original.

Si Xcode marca un error al compilar, cópialo y pégamelo.

---

## 2. Tomar las capturas de pantalla

Apple pide entre 1 y 10 capturas en formato 16:10. Tamaños válidos: **2880×1800**, 2560×1600, 1440×900 o 1280×800.

1. Pon un fondo de pantalla bonito y limpia el Escritorio.
2. Arrastra un archivo, pulsa Shift y, con la rueda visible, toma la captura con **⇧⌘3** (pantalla completa).
   Truco: si se te hace difícil, usa **⇧⌘5 → Opciones → Temporizador de 5 segundos**.
3. La pantalla de tu MacBook Air no es 16:10, así que hay que recortar. En Terminal:
   ```
   cd ~/Desktop
   sips -c 1800 2880 "Captura de pantalla*.png"
   ```
   Si te dice que la imagen es más pequeña, usa `sips -c 1600 2560` en su lugar.
4. Ideas de capturas: la rueda sobre un PDF, la rueda sobre una foto, el aviso "Listo", la ventana de Ajustes.

---

## 3. Páginas de soporte y privacidad

Ya están publicadas:

- Soporte: `https://hebexort771.github.io/RuedaConvert/`
- Privacidad: `https://hebexort771.github.io/RuedaConvert/privacidad.html`

---

## 4. Crear la app en App Store Connect

1. Cuando Apple apruebe tu inscripción, vuelve a Xcode → **Signing & Capabilities → Team** y elige tu equipo de pago (ya no "Personal Team"). Con la firma automática, Xcode registra el identificador `com.hebergomez.ruedaconvert` por ti.
2. Entra a <https://appstoreconnect.apple.com> → **Apps → + → Nueva app**:
   - Plataforma: **macOS**
   - Nombre: **RuedaConvert** (si ya está tomado, prueba "RuedaConvert – Conversor")
   - Idioma principal: **Español (México)**
   - ID de paquete: **com.hebergomez.ruedaconvert**
   - SKU: `ruedaconvert-mac-001` (es interno, cualquiera sirve)
3. Llena la ficha con los textos del final de esta guía y sube las capturas.
4. **Privacidad de la app → Empezar → "No, no recopilamos datos de esta app".**
5. **Clasificación por edad:** responde "No" a todo → queda en 4+.
6. **Precio:** elige *Gratis* o un precio. Para cobrar tienes que aceptar el acuerdo de apps de pago y llenar datos bancarios y de impuestos en *Negocio*.

---

## 5. Subir la app

1. En Xcode, arriba en el selector de destino, elige **Any Mac (Apple Silicon, Intel)**.
2. Menú **Product → Archive**. Al terminar se abre el *Organizer*.
3. **Distribute App → App Store Connect → Distribute**. Deja las opciones por defecto.
4. Espera el correo de Apple diciendo que el build terminó de procesarse (suele tardar menos de una hora).
5. En App Store Connect, en la versión 1.0, sección **Compilación**, pulsa **+** y elige ese build.

---

## 6. Enviar a revisión

1. En **Información para la revisión de la app**, pega las *Notas para el revisor* del final (en inglés, que es lo que leen los revisores). No hace falta cuenta de prueba.
2. Pulsa **Añadir para revisión → Enviar**.
3. La revisión suele tardar uno o dos días. Si la rechazan, copia el mensaje de Apple y pégamelo: casi siempre se arregla con un cambio pequeño o una explicación.

---

## 7. Actualizaciones futuras

En Xcode → target **RuedaConvert → General**, sube **Version** (1.0 → 1.1) y **Build** (1 → 2). Luego crea una versión nueva en App Store Connect (**+ Versión**), vuelve a hacer **Product → Archive** y repite los pasos 5 y 6.

---

## Textos para la tienda

### Español (México)

**Nombre** (máx. 30): `RuedaConvert`

**Subtítulo** (máx. 30): `Convierte arrastrando + Shift`

**Texto promocional** (máx. 170):
```
Arrastra cualquier archivo, pulsa Shift y elige el formato en la rueda. PDF a Word, fotos a JPG, texto de imágenes y más, sin salir de lo que estás haciendo.
```

**Descripción:**
```
RuedaConvert convierte archivos con un solo gesto.

Empieza a arrastrar un archivo desde Finder o el Escritorio, pulsa Shift y aparece una rueda con los formatos disponibles. Suéltalo sobre el que quieras y listo: el archivo convertido aparece al instante.

QUÉ PUEDES CONVERTIR
• PDF → Word (DOCX), JPG, PNG o texto
• Fotos (HEIC, JPG, PNG, WEBP, GIF, TIFF) → JPG, PNG, HEIC o PDF
• Fotos y PDF escaneados → texto, con reconocimiento de texto (OCR) en español e inglés
• Documentos (Word, RTF, ODT, HTML, TXT, Markdown) → PDF, Word, TXT, RTF o HTML

PRIVADO DE VERDAD
Todo se convierte en tu Mac. Tus archivos nunca se suben a internet y la app no recopila ningún dato.

DISCRETO
RuedaConvert vive en la barra de menú y solo aparece cuando pulsas Shift mientras arrastras un archivo. Puedes pausarlo cuando quieras.

DETALLES
• Convierte varios archivos a la vez.
• Nunca sobrescribe nada: si el nombre existe, crea una copia numerada.
• PDF de varias páginas → una imagen por página.
• Guarda en Descargas o junto al archivo original (tú eliges en Ajustes).
• Puede abrirse sola al iniciar sesión.
```

**Palabras clave** (máx. 100, separadas por comas, sin espacios):
```
convertir,pdf,word,docx,jpg,png,heic,ocr,texto,imagen,conversor,archivos,arrastrar,foto
```

**Categoría:** Productividad (secundaria: Utilidades)

**URL de soporte:** `https://hebexort771.github.io/RuedaConvert/`
**URL de la política de privacidad:** `https://hebexort771.github.io/RuedaConvert/privacidad.html`

**Copyright:** `2026 Heber Gomez`

### English (U.S.) — opcional, para llegar a más países

En App Store Connect: **Información de la app → idioma (arriba a la derecha) → Añadir idioma → English (U.S.)**.

**Subtitle:** `Convert files by drag + Shift`

**Promotional text:**
```
Drag any file, press Shift and pick a format from the wheel. PDF to Word, photos to JPG, text from images and more, without leaving what you're doing.
```

**Description:**
```
RuedaConvert converts files with a single gesture.

Start dragging a file from Finder or your Desktop, press Shift, and a wheel with the available formats appears. Drop the file on the one you want and you're done.

WHAT YOU CAN CONVERT
• PDF → Word (DOCX), JPG, PNG or text
• Photos (HEIC, JPG, PNG, WEBP, GIF, TIFF) → JPG, PNG, HEIC or PDF
• Photos and scanned PDFs → text, with on-device text recognition (OCR)
• Documents (Word, RTF, ODT, HTML, TXT, Markdown) → PDF, Word, TXT, RTF or HTML

TRULY PRIVATE
Everything is converted on your Mac. Your files are never uploaded and the app collects no data.

OUT OF THE WAY
RuedaConvert lives in the menu bar and only appears when you press Shift while dragging a file.

DETAILS
• Convert several files at once.
• Never overwrites anything.
• Multi-page PDFs become one image per page.
• Saves to Downloads or next to the original file (your choice in Settings).
```

**Keywords:**
```
convert,converter,pdf,word,docx,jpg,png,heic,ocr,text,image,files,drag,photo
```

### Notas para el revisor (pegar tal cual, en inglés)

```
RuedaConvert is a menu bar app (LSUIElement). On first launch it shows a welcome window explaining how to use it. It can be reopened at any time from the menu bar icon > "Ajustes…", or by opening the app again from the Applications folder.

How to test:
1. Start dragging any PDF or image file from Finder or the Desktop.
2. While still holding the mouse button, press and hold Shift. A circular wheel with output formats appears under the cursor.
3. Drop the file on a format (for example DOCX or JPG). The converted file is saved to the Downloads folder and a confirmation message appears at the bottom of the screen. Clicking it reveals the file in Finder.
4. Dropping on the center (X) cancels.

About permissions and privacy:
- The app uses a global monitor for left-mouse-down/drag events only, to know when a drag is in progress. It does not monitor the keyboard (it reads the current Shift state with NSEvent.modifierFlags) and requires no Accessibility permission.
- It reads only the file names on the drag pasteboard to decide which formats to offer.
- Converted files are saved to Downloads (com.apple.security.files.downloads.read-write). Optionally, the user can grant access to a folder through an NSOpenPanel in Settings so that files are saved next to the original (security-scoped bookmark).
- All conversions happen on device (PDFKit, ImageIO, Vision, AppKit). No network access, no data collection.
- "Open at login" is off by default and only enabled by the user in Settings (SMAppService).
```
