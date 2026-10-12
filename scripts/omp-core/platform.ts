import URL from "../../build/upstream/native-runtime/node_modules/core-js-pure/actual/url/index.js";
import { File } from "../../os/deps/quickbeam/priv/ts/blob.ts";
import { FormData } from "../../os/deps/quickbeam/priv/ts/form-data.ts";

// OMP's schema library initializes these constructors eagerly. They are
// in-memory data types, not grants of Node/Bun, network or filesystem access.
Object.assign(globalThis, { URL, File, FormData });
