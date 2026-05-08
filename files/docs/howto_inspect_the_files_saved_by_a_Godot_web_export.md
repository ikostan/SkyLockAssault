
# How to inspect the files saved by a Godot web export

## Introduction

To inspect the files saved by a Godot web export, you must look into
Chrome's IndexedDB. Because browsers cannot write directly to a
physical hard drive for security reasons, the web exporter uses
Emscripten's IDBFS to simulate a virtual file system
(your `user://` directory) and saves it into the browser's internal
IndexedDB storage.

Here is the complete procedure to inspect those files and read their
exact contents before and after encryption.

### How to Locate the Virtual File System

1. Open your deployed web game in Google Chrome.
2. Open Chrome Developer Tools (press **F12** or **Ctrl+Shift+I**).
3. Navigate to the **Application** tab at the top.
4. On the left sidebar, locate the **Storage** section and expand
   **IndexedDB**.
5. Look for the database named **`/userfs`** and expand it.
6. Click on **`FILE_DATA`**. On the right side, you will see a list
   of the exact paths saved by the engine
   (e.g., `/userfs/godot/app_userdata/SkyLockAssault/settings.cfg`).

### How to Read the File Contents

Because IndexedDB stores file contents as raw byte arrays, simply
clicking on the file in the Application tab will not show you the
text. You must use a JavaScript snippet to extract the bytes and
decode them into a readable format.

1. Switch to the **Console** tab in Chrome Developer Tools.
2. **Critical Step:** Locate the Execution Context dropdown at the
   top-left of the Console panel (it defaults to saying **`top`**).
   Click the dropdown and change it from `top` to **`index.html`**
   (or the specific iframe name running your game).
   If you do not change this, the script will return an error because
   it cannot find the database within the top-level page context.
3. Paste and run the following JavaScript script:

<!-- markdownlint-disable line-length -->
```javascript
const request = indexedDB.open('/userfs');
request.onsuccess = (event) => {
    const db = event.target.result;
    const store = db.transaction(['FILE_DATA'], 'readonly').objectStore('FILE_DATA');
    
    // Target your specific settings file path
    store.get('/userfs/godot/app_userdata/SkyLockAssault/settings.cfg').onsuccess = (e) => {
        const data = e.target.result;
        if (data && data.contents) {
            // Decodes the raw byte array into readable text
            console.log("File Contents:\n\n", new TextDecoder().decode(data.contents));
        } else {
            console.log("File not found or empty.");
        }
    };
};
```
<!-- markdownlint-enable line-length -->

When you run this script, it will print the raw output of the file
to the console. If your failsafe was triggered, you will see the
readable `[Settings]` configuration plaintext. If the encryption
pipeline was successful, you will see the "GDEC" magic header followed
by scrambled, encrypted characters.
