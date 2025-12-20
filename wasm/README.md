# WASM Support

## odin.js

This file is based on the original Odin compiler's JavaScript runtime. It includes an additional
function called `load_file_sync` used to load assets. The function works in both localhost and
HTTPS-served environments:

```js
load_file_sync: (pathPtr, pathLen, bufferPtr, bufferSize) => {
    const path = wasmMemoryInterface.loadString(pathPtr, pathLen);

    try {
        const xhr = new XMLHttpRequest();
        xhr.open('GET', path, false); // false = synchronous
        xhr.overrideMimeType('text/plain; charset=x-user-defined');
        xhr.send();

        if (xhr.status === 200) {
            const responseText = xhr.responseText;
            const bytes = new Uint8Array(responseText.length);
            for (let i = 0; i < responseText.length; i++) {
                bytes[i] = responseText.charCodeAt(i) & 0xff;
            }

            if (bytes.byteLength > bufferSize) {
                console.error(`File too large: ${bytes.byteLength} > ${bufferSize}`);
                return -1;
            }

            const targetBuffer = new Uint8Array(
                wasmMemoryInterface.memory.buffer,
                bufferPtr,
                bytes.byteLength
            );
            targetBuffer.set(bytes);

            return bytes.byteLength;
        }

        console.error(`HTTP ${xhr.status} loading ${path}`);
        return -1;

    } catch (e) {
        console.error(`Error loading ${path}:`, e);
        return -1;
    }
}
```

### Current Limitation

The current implementation requires a pre-allocated buffer to store file data, and that
buffer has a fixed size limit. This constraint imposes a hard limit on maximum asset size and
multiple consecutive calls may be inefficient due to buffer overhead.
