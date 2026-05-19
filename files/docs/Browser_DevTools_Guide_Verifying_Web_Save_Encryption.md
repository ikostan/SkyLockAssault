# Browser DevTools Guide — Verifying Web Save Encryption in Godot 4.5

This guide explains exactly how to use the provided JavaScript debugging
scripts inside browser Developer Tools to inspect, validate, and
troubleshoot encrypted save data stored in IndexedDB for the Web export
of [SkyLockAssault GitHub Repository](https://github.com/ikostan/SkyLockAssault).

---

## Purpose of These Tests

The JavaScript snippets are designed to verify:

* whether save files exist
* whether encryption actually occurred
* whether encryption used a valid key
* whether plaintext data leaked into IndexedDB
* whether corrupted saves are stuck in recovery loops
* whether the CI/CD salt injection succeeded

These tests directly inspect Godot’s browser virtual filesystem (`/userfs`)
stored in IndexedDB.

---

## Browser Requirements

Supported browsers:

* [Google Chrome](https://www.google.com/chrome/?utm_source=chatgpt.com)
* [Mozilla Firefox](https://www.mozilla.org/firefox/?utm_source=chatgpt.com)

Chrome is strongly recommended because its IndexedDB tooling is easier
to inspect visually.

---

## Opening Developer Tools

### Chrome

Open DevTools using:

```text
F12
```

or:

```text
Ctrl + Shift + I
```

---

### CRITICAL — Set Correct JavaScript Execution Context

This is the most important step.

When running JavaScript against Godot Web exports, the console context
MUST target the game iframe/page itself.

If you leave the context set to:

```text
top
```

your scripts will fail to access the Godot IndexedDB storage.

---

## How to Change Context in Chrome

Inside DevTools Console:

1. Open the **Console** tab
2. Locate the context dropdown near the top-left
3. Change it from:

```text
top
```

to:

```text
index.html
```

---

## What Happens If Context Is Wrong

Symptoms include:

```text
undefined
```

or:

```text
IndexedDB database not found
```

or empty query results.

The scripts may appear to run successfully while returning no save data.

---

## Understanding Godot Web Storage

Godot Web exports store files inside:

```text
/userfs
```

Internally this maps to:

```text
IndexedDB
```

The save file path used by the game is:

```text
/userfs/godot/app_userdata/SkyLockAssault/settings.cfg
```

This file is what the scripts inspect.

---

## Script 1 — Verify Save File Exists

### Script 1 Purpose

Confirms:

* IndexedDB is accessible
* the save file exists
* file size looks reasonable

This is the first script you should run.

---

### Script 1

Use this to confirm basic IndexedDB access and check the file size.

<!-- markdownlint-disable line-length -->
```javascript
const request = indexedDB.open('/userfs');

// 1. Catches browser-level blocks (e.g., third-party cookies disabled, strict privacy mode)
request.onerror = (event) => {
    console.error("❌ IndexedDB failed to open. Check execution context or browser privacy settings.", event.target.error);
};

request.onsuccess = (event) => {
    const db = event.target.result;

    // 2. Catches cases where the DB exists, but Godot hasn't created the object stores yet
    try {
        const store = db
            .transaction(['FILE_DATA'], 'readonly')
            .objectStore('FILE_DATA');

        const getRequest = store.get('/userfs/godot/app_userdata/SkyLockAssault/settings.cfg');

        // 3. Catches failures specific to reading this exact file
        getRequest.onerror = (e) => {
             console.error("❌ Failed to read from the FILE_DATA object store:", e.target.error);
        };

        getRequest.onsuccess = (e) => {
            const data = e.target.result;

            if (data && data.contents) {
                console.log(
                    "✅ File size in bytes:",
                    data.contents.byteLength
                );
            } else {
                console.log("⚠️ Save file not found. Game may not have saved yet.");
            }
        };
    } catch (err) {
        console.error("❌ Failed to open transaction. The Godot file system may not be initialized yet.", err);
    }
};
```
<!-- markdownlint-enable line-length -->

---

### How to Run It

1. Open DevTools
2. Switch context to `index.html`
3. Paste script into Console
4. Press Enter

---

### Expected Healthy Output

Example:

```text
File size in bytes: 1276
```

This means:

* save exists
* IndexedDB access works
* file contains encrypted data

---

### Bad Output Cases

#### Missing File

```text
Save file not found.
```

Possible causes:

* save was never created
* game failed before save
* corrupted file got auto-deleted
* wrong execution context selected

---

#### Very Small File Size

Example:

```text
File size in bytes: 12
```

Usually indicates:

* failed encryption
* truncated write
* broken save logic

---

## Script 2 — Detect Hollow Encryption

### Script 2 Purpose

This is the most important security validation test.

It determines whether the game truly encrypted the save or merely
wrapped plaintext using an empty encryption key.

---

### Why This Happens

If:

```gdscript
_get_encryption_key()
```

returns an empty string:

```gdscript
""
```

Godot still creates a file with encryption headers (`GDEC`) even
though the content is effectively plaintext.

This creates “fake encryption.”

---

### Script 2

Use this to verify that the CI/CD salt injection worked and the
data is actually encrypted (unreadable).

<!-- markdownlint-disable line-length -->
```javascript
const request = indexedDB.open('/userfs');

request.onerror = (event) => {
    console.error("❌ IndexedDB failed to open. Check execution context or browser privacy settings.", event.target.error);
};

request.onsuccess = (event) => {
    const db = event.target.result;

    try {
        const store = db
            .transaction(['FILE_DATA'], 'readonly')
            .objectStore('FILE_DATA');

        const getRequest = store.get('/userfs/godot/app_userdata/SkyLockAssault/settings.cfg');

        getRequest.onerror = (e) => {
             console.error("❌ Failed to read from the FILE_DATA object store:", e.target.error);
        };

        getRequest.onsuccess = (e) => {
            const data = e.target.result;

            if (data && data.contents) {
                const decoded = new TextDecoder().decode(data.contents);
                console.log("✅ Decoded File Contents:\n\n", decoded);
            } else {
                console.log("⚠️ Save file not found. Game may not have saved yet.");
            }
        };
    } catch (err) {
        console.error("❌ Failed to open transaction. The Godot file system may not be initialized yet.", err);
    }
};
```
<!-- markdownlint-enable line-length -->

---

### How to Interpret Results

#### GOOD — Proper Encryption

Expected output:

```text
GDEC▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
```

or unreadable garbage characters.

This means:

* encryption key exists
* encryption worked correctly
* plaintext is protected

---

#### BAD — Hollow Encryption

If you see readable settings like:

```ini
master_volume=0.8
music_volume=0.6
fullscreen=true
```

then encryption failed.

This means:

* runtime key was empty
* CI/CD salt injection failed
* WebAssembly initialization likely crashed early
* save data is insecure

---

### What “GDEC” Means

You may see:

```text
GDEC
```

at the beginning of decoded output.

This is normal.

It is Godot’s encrypted file signature/header.

The important part is whether the remaining content is readable.

---

## Script 3 — Inspect Raw IndexedDB Object

### Script 3 Purpose

Allows deep inspection of the actual stored file object.

Useful for debugging:

* missing fields
* corrupted blobs
* malformed writes
* unexpected metadata

---

### Script 3

Use this to view the raw Godot file object (timestamp,
mode, and the raw Uint8Array payload).

<!-- markdownlint-disable line-length -->
```javascript
const request = indexedDB.open('/userfs');

request.onerror = (event) => {
    console.error("❌ IndexedDB failed to open. Check execution context or browser privacy settings.", event.target.error);
};

request.onsuccess = (event) => {
    const db = event.target.result;

    try {
        const store = db
            .transaction(['FILE_DATA'], 'readonly')
            .objectStore('FILE_DATA');

        const getRequest = store.get('/userfs/godot/app_userdata/SkyLockAssault/settings.cfg');

        getRequest.onerror = (e) => {
             console.error("❌ Failed to read from the FILE_DATA object store:", e.target.error);
        };

        getRequest.onsuccess = (e) => {
            const data = e.target.result;

            if (data) {
                console.log("✅ Raw IndexedDB Object:\n", data);
            } else {
                console.log("⚠️ Save file not found. Game may not have saved yet.");
            }
        };
    } catch (err) {
        console.error("❌ Failed to open transaction. The Godot file system may not be initialized yet.", err);
    }
};
```
<!-- markdownlint-enable line-length -->

---

### Expected Output Structure

Example:

```javascript
{
    timestamp: 1747070000000,
    mode: 33206,
    contents: Uint8Array(...)
}
```

---

### Important Field

#### `contents`

This contains the actual encrypted file bytes.

If `contents` is:

```text
undefined
```

or empty:

* save write failed
* IndexedDB transaction failed
* file corruption occurred

---

## Script 4 — Force Corruption Recovery Test

### Script 4 Purpose

Tests whether the game properly auto-recovers from corrupted encrypted saves.

---

### WARNING

This intentionally damages the save file.

Use only in testing environments.

---

### Script 4

Use this to intentionally corrupt the file to test Godot's
auto-recovery system. Note the transaction is set to readwrite here.

<!-- markdownlint-disable line-length -->
```javascript
const request = indexedDB.open('/userfs');

request.onerror = (event) => {
    console.error("❌ IndexedDB failed to open. Check execution context or browser privacy settings.", event.target.error);
};

request.onsuccess = (event) => {
    const db = event.target.result;

    try {
        // Must be 'readwrite' to push the corrupted file back into the database
        const transaction = db.transaction(['FILE_DATA'], 'readwrite');
        const store = transaction.objectStore('FILE_DATA');

        const getRequest = store.get('/userfs/godot/app_userdata/SkyLockAssault/settings.cfg');

        getRequest.onerror = (e) => {
             console.error("❌ Failed to read from the FILE_DATA object store:", e.target.error);
        };

        getRequest.onsuccess = (e) => {
            const data = e.target.result;

            if (!data || !data.contents) {
                console.log("⚠️ Save file not found. Cannot perform corruption test.");
                return;
            }

            // Target index 10 to safely skip Godot's 4-byte 'GDEC' header and target the encrypted payload
            data.contents[10] ^= 255;

            const putRequest = store.put(data);
            
            putRequest.onsuccess = () => {
                console.log("☢️ Save file intentionally corrupted. Refresh the page to test recovery.");
            };
            
            putRequest.onerror = (err) => {
                console.error("❌ Failed to write corrupted data back to IndexedDB.", err.target.error);
            };
        };
    } catch (err) {
        console.error("❌ Failed to open transaction. The Godot file system may not be initialized yet.", err);
    }
};
```
<!-- markdownlint-enable line-length -->

---

### What This Script Does

This line:

```javascript
data.contents[10] ^= 255;
```

modifies one byte inside the encrypted save.

That is enough to:

* break MD5 validation
* trigger Godot decryption failure
* simulate real corruption

---

### Expected Recovery Behavior

After corruption:

1. Refresh the page
2. Game attempts decryption
3. Decryption fails
4. Recovery system activates

Expected logs:

```text
🚨 DECRYPTION FAILED
🗑️ Auto-deleting corrupted/orphaned save file
```

---

### Successful Recovery Indicators

After refresh:

* game boots normally
* settings reset cleanly
* no infinite loop
* new save file generated

---

### Visual IndexedDB Inspection (Chrome)

Chrome also allows manual inspection without scripts.

---

### How to Open IndexedDB Viewer

Inside DevTools:

```text
Application
→ IndexedDB
→ /userfs
→ FILE_DATA
```

You can manually browse:

```text id="v4i1h2"
/userfs/godot/app_userdata/SkyLockAssault/settings.cfg
```

---

### What to Look For

#### Healthy Save

* binary `contents`
* non-trivial file size
* timestamp updates after saves

---

#### Broken Save

* tiny file size
* empty contents
* readable plaintext
* missing object

---

## Common Mistakes

| Problem                | Cause                      |
|------------------------|----------------------------|
| Scripts return nothing | Wrong execution context    |
| `Save file not found`  | Save never created         |
| Readable plaintext     | Empty encryption key       |
| Infinite Error 16 loop | Missing auto-recovery      |
| IndexedDB missing      | Game never initialized     |
| `undefined` results    | Wrong object store or path |

---

## Recommended Debugging Workflow

Use this exact order:

1. Launch game
2. Open DevTools
3. Switch context to `index.html`
4. Run Script 1
5. Verify file exists
6. Run Script 2
7. Confirm unreadable encrypted data
8. Run corruption test
9. Refresh page
10. Verify auto-recovery works

---

## Final Validation Criteria

The implementation is considered secure and working correctly only if:

* IndexedDB save exists
* plaintext cannot be decoded
* no empty-key errors occur
* corrupted saves self-heal
* browser refresh does not enter infinite recovery loops
* WebAssembly initializes without silent crashes
