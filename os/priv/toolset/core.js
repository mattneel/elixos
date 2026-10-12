(() => {
  var __create = Object.create;
  var __getProtoOf = Object.getPrototypeOf;
  var __defProp = Object.defineProperty;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  function __accessProp(key) {
    return this[key];
  }
  var __toESMCache_node;
  var __toESMCache_esm;
  var __toESM = (mod, isNodeMode, target) => {
    var canCache = mod != null && typeof mod === "object";
    if (canCache) {
      var cache = isNodeMode ? __toESMCache_node ??= new WeakMap : __toESMCache_esm ??= new WeakMap;
      var cached = cache.get(mod);
      if (cached)
        return cached;
    }
    target = mod != null ? __create(__getProtoOf(mod)) : {};
    const to = isNodeMode || !mod || !mod.__esModule || !__hasOwnProp.call(mod, "default") ? __defProp(target, "default", { value: mod, enumerable: true }) : target;
    if (mod && typeof mod === "object" || typeof mod === "function") {
      for (let key of __getOwnPropNames(mod))
        if (!__hasOwnProp.call(to, key))
          __defProp(to, key, {
            get: __accessProp.bind(mod, key),
            enumerable: true
          });
    }
    if (canCache)
      cache.set(mod, to);
    return to;
  };
  var __commonJS = (cb, mod) => () => (mod || cb((mod = { exports: {} }).exports, mod), mod.exports);
  var __require = /* @__PURE__ */ ((x) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x, {
    get: (a, b) => (typeof require !== "undefined" ? require : a)[b]
  }) : x)(function(x) {
    if (typeof require !== "undefined")
      return require.apply(this, arguments);
    throw Error('Dynamic require of "' + x + '" is not supported');
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/fails.js
  var require_fails = __commonJS(function(exports, module) {
    module.exports = function(exec) {
      try {
        return !!exec();
      } catch (error) {
        return true;
      }
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-bind-native.js
  var require_function_bind_native = __commonJS(function(exports, module) {
    var fails = require_fails();
    module.exports = !fails(function() {
      var test = function() {}.bind();
      return typeof test != "function" || test.hasOwnProperty("prototype");
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-uncurry-this.js
  var require_function_uncurry_this = __commonJS(function(exports, module) {
    var NATIVE_BIND = require_function_bind_native();
    var FunctionPrototype = Function.prototype;
    var call = FunctionPrototype.call;
    var uncurryThisWithBind = NATIVE_BIND && FunctionPrototype.bind.bind(call, call);
    module.exports = NATIVE_BIND ? uncurryThisWithBind : function(fn) {
      return function() {
        return call.apply(fn, arguments);
      };
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/classof-raw.js
  var require_classof_raw = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var toString = uncurryThis({}.toString);
    var stringSlice = uncurryThis("".slice);
    module.exports = function(it) {
      return stringSlice(toString(it), 8, -1);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/indexed-object.js
  var require_indexed_object = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var fails = require_fails();
    var classof = require_classof_raw();
    var $Object = Object;
    var split = uncurryThis("".split);
    module.exports = fails(function() {
      return !$Object("z").propertyIsEnumerable(0);
    }) ? function(it) {
      return classof(it) === "String" ? split(it, "") : $Object(it);
    } : $Object;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-null-or-undefined.js
  var require_is_null_or_undefined = __commonJS(function(exports, module) {
    module.exports = function(it) {
      return it === null || it === undefined;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/require-object-coercible.js
  var require_require_object_coercible = __commonJS(function(exports, module) {
    var isNullOrUndefined = require_is_null_or_undefined();
    var $TypeError = TypeError;
    module.exports = function(it) {
      if (isNullOrUndefined(it))
        throw new $TypeError("Can't call method on " + it);
      return it;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-indexed-object.js
  var require_to_indexed_object = __commonJS(function(exports, module) {
    var IndexedObject = require_indexed_object();
    var requireObjectCoercible = require_require_object_coercible();
    module.exports = function(it) {
      return IndexedObject(requireObjectCoercible(it));
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/add-to-unscopables.js
  var require_add_to_unscopables = __commonJS(function(exports, module) {
    module.exports = function() {};
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/iterators.js
  var require_iterators = __commonJS(function(exports, module) {
    module.exports = Object.create ? Object.create(null) : {};
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/global-this.js
  var require_global_this = __commonJS(function(exports, module) {
    var check = function(it) {
      return it && it.Math === Math && it;
    };
    module.exports = check(typeof globalThis == "object" && globalThis) || check(typeof window == "object" && window) || check(typeof self == "object" && self) || check(typeof global == "object" && global) || check(typeof exports == "object" && exports) || function() {
      return this;
    }() || Function("return this")();
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-callable.js
  var require_is_callable = __commonJS(function(exports, module) {
    var documentAll = typeof document == "object" && document.all;
    module.exports = typeof documentAll == "undefined" && documentAll !== undefined ? function(argument) {
      return typeof argument == "function" || argument === documentAll;
    } : function(argument) {
      return typeof argument == "function";
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/weak-map-basic-detection.js
  var require_weak_map_basic_detection = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var isCallable = require_is_callable();
    var WeakMap2 = globalThis2.WeakMap;
    module.exports = isCallable(WeakMap2) && /native code/.test(String(WeakMap2));
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-object.js
  var require_is_object = __commonJS(function(exports, module) {
    var isCallable = require_is_callable();
    module.exports = function(it) {
      return typeof it == "object" ? it !== null : isCallable(it);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/descriptors.js
  var require_descriptors = __commonJS(function(exports, module) {
    var fails = require_fails();
    module.exports = !fails(function() {
      return Object.defineProperty({}, 1, { get: function() {
        return 7;
      } })[1] !== 7;
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/document-create-element.js
  var require_document_create_element = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var isObject = require_is_object();
    var document2 = globalThis2.document;
    var EXISTS = isObject(document2) && isObject(document2.createElement);
    module.exports = function(it) {
      return EXISTS ? document2.createElement(it) : {};
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/ie8-dom-define.js
  var require_ie8_dom_define = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var fails = require_fails();
    var createElement = require_document_create_element();
    module.exports = !DESCRIPTORS && !fails(function() {
      return Object.defineProperty(createElement("div"), "a", {
        get: function() {
          return 7;
        }
      }).a !== 7;
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/v8-prototype-define-bug.js
  var require_v8_prototype_define_bug = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var fails = require_fails();
    module.exports = DESCRIPTORS && fails(function() {
      return Object.defineProperty(function() {}, "prototype", {
        value: 42,
        writable: false
      }).prototype !== 42;
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/an-object.js
  var require_an_object = __commonJS(function(exports, module) {
    var isObject = require_is_object();
    var $String = String;
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isObject(argument))
        return argument;
      throw new $TypeError($String(argument) + " is not an object");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-call.js
  var require_function_call = __commonJS(function(exports, module) {
    var NATIVE_BIND = require_function_bind_native();
    var call = Function.prototype.call;
    module.exports = NATIVE_BIND ? call.bind(call) : function() {
      return call.apply(call, arguments);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/path.js
  var require_path = __commonJS(function(exports, module) {
    module.exports = {};
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/get-built-in.js
  var require_get_built_in = __commonJS(function(exports, module) {
    var path = require_path();
    var globalThis2 = require_global_this();
    var isCallable = require_is_callable();
    var aFunction = function(variable) {
      return isCallable(variable) ? variable : undefined;
    };
    module.exports = function(namespace, method) {
      return arguments.length < 2 ? aFunction(path[namespace]) || aFunction(globalThis2[namespace]) : path[namespace] && path[namespace][method] || globalThis2[namespace] && globalThis2[namespace][method];
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-is-prototype-of.js
  var require_object_is_prototype_of = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    module.exports = uncurryThis({}.isPrototypeOf);
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/environment-user-agent.js
  var require_environment_user_agent = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var navigator = globalThis2.navigator;
    var userAgent = navigator && navigator.userAgent;
    module.exports = userAgent ? String(userAgent) : "";
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/environment-v8-version.js
  var require_environment_v8_version = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var userAgent = require_environment_user_agent();
    var process = globalThis2.process;
    var Deno = globalThis2.Deno;
    var versions = process && process.versions || Deno && Deno.version;
    var v8 = versions && versions.v8;
    var match;
    var version;
    if (v8) {
      match = v8.split(".");
      version = match[0] > 0 && match[0] < 4 ? 1 : +(match[0] + match[1]);
    }
    if (!version && userAgent) {
      match = userAgent.match(/Edge\/(\d+)/);
      if (!match || match[1] >= 74) {
        match = userAgent.match(/Chrome\/(\d+)/);
        if (match)
          version = +match[1];
      }
    }
    module.exports = version;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/symbol-constructor-detection.js
  var require_symbol_constructor_detection = __commonJS(function(exports, module) {
    var V8_VERSION = require_environment_v8_version();
    var fails = require_fails();
    var globalThis2 = require_global_this();
    var $String = globalThis2.String;
    module.exports = !!Object.getOwnPropertySymbols && !fails(function() {
      var symbol = Symbol("symbol detection");
      return !$String(symbol) || !(Object(symbol) instanceof Symbol) || !Symbol.sham && V8_VERSION && V8_VERSION < 41;
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/use-symbol-as-uid.js
  var require_use_symbol_as_uid = __commonJS(function(exports, module) {
    var NATIVE_SYMBOL = require_symbol_constructor_detection();
    module.exports = NATIVE_SYMBOL && !Symbol.sham && typeof Symbol.iterator == "symbol";
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-symbol.js
  var require_is_symbol = __commonJS(function(exports, module) {
    var getBuiltIn = require_get_built_in();
    var isCallable = require_is_callable();
    var isPrototypeOf = require_object_is_prototype_of();
    var USE_SYMBOL_AS_UID = require_use_symbol_as_uid();
    var $Object = Object;
    module.exports = USE_SYMBOL_AS_UID ? function(it) {
      return typeof it == "symbol";
    } : function(it) {
      var $Symbol = getBuiltIn("Symbol");
      return isCallable($Symbol) && isPrototypeOf($Symbol.prototype, $Object(it));
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/try-to-string.js
  var require_try_to_string = __commonJS(function(exports, module) {
    var $String = String;
    module.exports = function(argument) {
      try {
        return $String(argument);
      } catch (error) {
        return "Object";
      }
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/a-callable.js
  var require_a_callable = __commonJS(function(exports, module) {
    var isCallable = require_is_callable();
    var tryToString = require_try_to_string();
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isCallable(argument))
        return argument;
      throw new $TypeError(tryToString(argument) + " is not a function");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/get-method.js
  var require_get_method = __commonJS(function(exports, module) {
    var aCallable = require_a_callable();
    var isNullOrUndefined = require_is_null_or_undefined();
    module.exports = function(V, P) {
      var func = V[P];
      return isNullOrUndefined(func) ? undefined : aCallable(func);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/ordinary-to-primitive.js
  var require_ordinary_to_primitive = __commonJS(function(exports, module) {
    var call = require_function_call();
    var isCallable = require_is_callable();
    var isObject = require_is_object();
    var $TypeError = TypeError;
    module.exports = function(input, pref) {
      var fn, val;
      if (pref === "string" && isCallable(fn = input.toString) && !isObject(val = call(fn, input)))
        return val;
      if (isCallable(fn = input.valueOf) && !isObject(val = call(fn, input)))
        return val;
      if (pref !== "string" && isCallable(fn = input.toString) && !isObject(val = call(fn, input)))
        return val;
      throw new $TypeError("Can't convert object to primitive value");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-pure.js
  var require_is_pure = __commonJS(function(exports, module) {
    module.exports = true;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/define-global-property.js
  var require_define_global_property = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var defineProperty = Object.defineProperty;
    module.exports = function(key, value) {
      try {
        defineProperty(globalThis2, key, { value, configurable: true, writable: true });
      } catch (error) {
        globalThis2[key] = value;
      }
      return value;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/shared-store.js
  var require_shared_store = __commonJS(function(exports, module) {
    var IS_PURE = require_is_pure();
    var globalThis2 = require_global_this();
    var defineGlobalProperty = require_define_global_property();
    var SHARED = "__core-js_shared__";
    var store = module.exports = globalThis2[SHARED] || defineGlobalProperty(SHARED, {});
    (store.versions || (store.versions = [])).push({
      version: "3.50.0",
      mode: IS_PURE ? "pure" : "global",
      copyright: "© 2013–2025 Denis Pushkarev (zloirock.ru), 2025–2026 CoreJS Company (core-js.io). All rights reserved.",
      license: "https://github.com/zloirock/core-js/blob/v3.50.0/LICENSE",
      source: "https://github.com/zloirock/core-js"
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/shared.js
  var require_shared = __commonJS(function(exports, module) {
    var store = require_shared_store();
    var create = Object.create || Object;
    module.exports = function(key, value) {
      return store[key] || (store[key] = value || create(null));
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-object.js
  var require_to_object = __commonJS(function(exports, module) {
    var requireObjectCoercible = require_require_object_coercible();
    var $Object = Object;
    module.exports = function(argument) {
      return $Object(requireObjectCoercible(argument));
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/has-own-property.js
  var require_has_own_property = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var toObject = require_to_object();
    var hasOwnProperty = uncurryThis({}.hasOwnProperty);
    module.exports = Object.hasOwn || function hasOwn(it, key) {
      return hasOwnProperty(toObject(it), key);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/uid.js
  var require_uid = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var id = 0;
    var postfix = Math.random();
    var toString = uncurryThis(1.1 .toString);
    module.exports = function(key) {
      return "Symbol(" + (key === undefined ? "" : key) + ")_" + toString(++id + postfix, 36);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/well-known-symbol.js
  var require_well_known_symbol = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var shared = require_shared();
    var hasOwn = require_has_own_property();
    var uid = require_uid();
    var NATIVE_SYMBOL = require_symbol_constructor_detection();
    var USE_SYMBOL_AS_UID = require_use_symbol_as_uid();
    var Symbol2 = globalThis2.Symbol;
    var WellKnownSymbolsStore = shared("wks");
    var createWellKnownSymbol = USE_SYMBOL_AS_UID ? Symbol2["for"] || Symbol2 : Symbol2 && Symbol2.withoutSetter || uid;
    module.exports = function(name) {
      if (!hasOwn(WellKnownSymbolsStore, name)) {
        WellKnownSymbolsStore[name] = NATIVE_SYMBOL && hasOwn(Symbol2, name) ? Symbol2[name] : createWellKnownSymbol("Symbol." + name);
      }
      return WellKnownSymbolsStore[name];
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-primitive.js
  var require_to_primitive = __commonJS(function(exports, module) {
    var call = require_function_call();
    var isObject = require_is_object();
    var isSymbol = require_is_symbol();
    var getMethod = require_get_method();
    var ordinaryToPrimitive = require_ordinary_to_primitive();
    var wellKnownSymbol = require_well_known_symbol();
    var $TypeError = TypeError;
    var TO_PRIMITIVE = wellKnownSymbol("toPrimitive");
    module.exports = function(input, pref) {
      if (!isObject(input) || isSymbol(input))
        return input;
      var exoticToPrim = getMethod(input, TO_PRIMITIVE);
      var result;
      if (exoticToPrim) {
        if (pref === undefined)
          pref = "default";
        result = call(exoticToPrim, input, pref);
        if (!isObject(result) || isSymbol(result))
          return result;
        throw new $TypeError("Can't convert object to primitive value");
      }
      if (pref === undefined)
        pref = "number";
      return ordinaryToPrimitive(input, pref);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-property-key.js
  var require_to_property_key = __commonJS(function(exports, module) {
    var toPrimitive = require_to_primitive();
    var isSymbol = require_is_symbol();
    module.exports = function(argument) {
      var key = toPrimitive(argument, "string");
      return isSymbol(key) ? key : key + "";
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-define-property.js
  var require_object_define_property = __commonJS(function(exports) {
    var DESCRIPTORS = require_descriptors();
    var IE8_DOM_DEFINE = require_ie8_dom_define();
    var V8_PROTOTYPE_DEFINE_BUG = require_v8_prototype_define_bug();
    var anObject = require_an_object();
    var toPropertyKey = require_to_property_key();
    var $TypeError = TypeError;
    var $defineProperty = Object.defineProperty;
    var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var ENUMERABLE = "enumerable";
    var CONFIGURABLE = "configurable";
    var WRITABLE = "writable";
    exports.f = DESCRIPTORS ? V8_PROTOTYPE_DEFINE_BUG ? function defineProperty(O, P, Attributes) {
      anObject(O);
      P = toPropertyKey(P);
      anObject(Attributes);
      if (typeof O === "function" && P === "prototype" && "value" in Attributes && WRITABLE in Attributes && !Attributes[WRITABLE]) {
        var current = $getOwnPropertyDescriptor(O, P);
        if (current && current[WRITABLE]) {
          O[P] = Attributes.value;
          Attributes = {
            configurable: CONFIGURABLE in Attributes ? Attributes[CONFIGURABLE] : current[CONFIGURABLE],
            enumerable: ENUMERABLE in Attributes ? Attributes[ENUMERABLE] : current[ENUMERABLE],
            writable: false
          };
        }
      }
      return $defineProperty(O, P, Attributes);
    } : $defineProperty : function defineProperty(O, P, Attributes) {
      anObject(O);
      P = toPropertyKey(P);
      anObject(Attributes);
      if (IE8_DOM_DEFINE)
        try {
          return $defineProperty(O, P, Attributes);
        } catch (error) {}
      if ("get" in Attributes || "set" in Attributes)
        throw new $TypeError("Accessors not supported");
      if ("value" in Attributes)
        O[P] = Attributes.value;
      return O;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/create-property-descriptor.js
  var require_create_property_descriptor = __commonJS(function(exports, module) {
    module.exports = function(bitmap, value) {
      return {
        enumerable: !(bitmap & 1),
        configurable: !(bitmap & 2),
        writable: !(bitmap & 4),
        value
      };
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/create-non-enumerable-property.js
  var require_create_non_enumerable_property = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var definePropertyModule = require_object_define_property();
    var createPropertyDescriptor = require_create_property_descriptor();
    module.exports = DESCRIPTORS ? function(object, key, value) {
      return definePropertyModule.f(object, key, createPropertyDescriptor(1, value));
    } : function(object, key, value) {
      object[key] = value;
      return object;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/shared-key.js
  var require_shared_key = __commonJS(function(exports, module) {
    var shared = require_shared();
    var uid = require_uid();
    var keys = shared("keys");
    module.exports = function(key) {
      return keys[key] || (keys[key] = uid(key));
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/hidden-keys.js
  var require_hidden_keys = __commonJS(function(exports, module) {
    module.exports = {};
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/internal-state.js
  var require_internal_state = __commonJS(function(exports, module) {
    var NATIVE_WEAK_MAP = require_weak_map_basic_detection();
    var globalThis2 = require_global_this();
    var isObject = require_is_object();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    var shared = require_shared_store();
    var sharedKey = require_shared_key();
    var hiddenKeys = require_hidden_keys();
    var OBJECT_ALREADY_INITIALIZED = "Object already initialized";
    var TypeError2 = globalThis2.TypeError;
    var WeakMap2 = globalThis2.WeakMap;
    var set;
    var get;
    var has;
    var enforce = function(it) {
      return has(it) ? get(it) : set(it, {});
    };
    var getterFor = function(TYPE) {
      return function(it) {
        var state;
        if (!isObject(it) || (state = get(it)).type !== TYPE) {
          throw new TypeError2("Incompatible receiver, " + TYPE + " required");
        }
        return state;
      };
    };
    if (NATIVE_WEAK_MAP || shared.state) {
      store = shared.state || (shared.state = new WeakMap2);
      store.get = store.get;
      store.has = store.has;
      store.set = store.set;
      set = function(it, metadata) {
        if (store.has(it))
          throw new TypeError2(OBJECT_ALREADY_INITIALIZED);
        metadata.facade = it;
        store.set(it, metadata);
        return metadata;
      };
      get = function(it) {
        return store.get(it) || {};
      };
      has = function(it) {
        return store.has(it);
      };
    } else {
      STATE = sharedKey("state");
      hiddenKeys[STATE] = true;
      set = function(it, metadata) {
        if (hasOwn(it, STATE))
          throw new TypeError2(OBJECT_ALREADY_INITIALIZED);
        metadata.facade = it;
        createNonEnumerableProperty(it, STATE, metadata);
        return metadata;
      };
      get = function(it) {
        return hasOwn(it, STATE) ? it[STATE] : {};
      };
      has = function(it) {
        return hasOwn(it, STATE);
      };
    }
    var store;
    var STATE;
    module.exports = {
      set,
      get,
      has,
      enforce,
      getterFor
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-apply.js
  var require_function_apply = __commonJS(function(exports, module) {
    var NATIVE_BIND = require_function_bind_native();
    var FunctionPrototype = Function.prototype;
    var apply = FunctionPrototype.apply;
    var call = FunctionPrototype.call;
    module.exports = typeof Reflect == "object" && Reflect.apply || (NATIVE_BIND ? call.bind(apply) : function() {
      return call.apply(apply, arguments);
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-uncurry-this-clause.js
  var require_function_uncurry_this_clause = __commonJS(function(exports, module) {
    var classofRaw = require_classof_raw();
    var uncurryThis = require_function_uncurry_this();
    module.exports = function(fn) {
      if (classofRaw(fn) === "Function")
        return uncurryThis(fn);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-property-is-enumerable.js
  var require_object_property_is_enumerable = __commonJS(function(exports) {
    var $propertyIsEnumerable = {}.propertyIsEnumerable;
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var NASHORN_BUG = getOwnPropertyDescriptor && !$propertyIsEnumerable.call({ 1: 2 }, 1);
    exports.f = NASHORN_BUG ? function propertyIsEnumerable(V) {
      var descriptor = getOwnPropertyDescriptor(this, V);
      return !!descriptor && descriptor.enumerable;
    } : $propertyIsEnumerable;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-get-own-property-descriptor.js
  var require_object_get_own_property_descriptor = __commonJS(function(exports) {
    var DESCRIPTORS = require_descriptors();
    var call = require_function_call();
    var propertyIsEnumerableModule = require_object_property_is_enumerable();
    var createPropertyDescriptor = require_create_property_descriptor();
    var toIndexedObject = require_to_indexed_object();
    var toPropertyKey = require_to_property_key();
    var hasOwn = require_has_own_property();
    var IE8_DOM_DEFINE = require_ie8_dom_define();
    var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    exports.f = DESCRIPTORS ? $getOwnPropertyDescriptor : function getOwnPropertyDescriptor(O, P) {
      O = toIndexedObject(O);
      P = toPropertyKey(P);
      if (IE8_DOM_DEFINE)
        try {
          return $getOwnPropertyDescriptor(O, P);
        } catch (error) {}
      if (hasOwn(O, P))
        return createPropertyDescriptor(!call(propertyIsEnumerableModule.f, O, P), O[P]);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-forced.js
  var require_is_forced = __commonJS(function(exports, module) {
    var fails = require_fails();
    var isCallable = require_is_callable();
    var replacement = /#|\.prototype\./;
    var isForced = function(feature, detection) {
      var value = data[normalize(feature)];
      return value === POLYFILL ? true : value === NATIVE ? false : isCallable(detection) ? fails(detection) : !!detection;
    };
    var normalize = isForced.normalize = function(string) {
      return String(string).replace(replacement, ".").toLowerCase();
    };
    var data = isForced.data = {};
    var NATIVE = isForced.NATIVE = "N";
    var POLYFILL = isForced.POLYFILL = "P";
    module.exports = isForced;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-bind-context.js
  var require_function_bind_context = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this_clause();
    var aCallable = require_a_callable();
    var NATIVE_BIND = require_function_bind_native();
    var bind = uncurryThis(uncurryThis.bind);
    module.exports = function(fn, that) {
      aCallable(fn);
      return that === undefined ? fn : NATIVE_BIND ? bind(fn, that) : function() {
        return fn.apply(that, arguments);
      };
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/export.js
  var require_export = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var apply = require_function_apply();
    var uncurryThis = require_function_uncurry_this_clause();
    var isCallable = require_is_callable();
    var getOwnPropertyDescriptor = require_object_get_own_property_descriptor().f;
    var isForced = require_is_forced();
    var path = require_path();
    var bind = require_function_bind_context();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    require_shared_store();
    var wrapConstructor = function(NativeConstructor) {
      var Wrapper = function(a, b, c) {
        if (this instanceof Wrapper) {
          switch (arguments.length) {
            case 0:
              return new NativeConstructor;
            case 1:
              return new NativeConstructor(a);
            case 2:
              return new NativeConstructor(a, b);
          }
          return new NativeConstructor(a, b, c);
        }
        return apply(NativeConstructor, this, arguments);
      };
      Wrapper.prototype = NativeConstructor.prototype;
      return Wrapper;
    };
    module.exports = function(options, source) {
      var TARGET = options.target;
      var GLOBAL = options.global;
      var STATIC = options.stat;
      var PROTO = options.proto;
      var nativeSource = GLOBAL ? globalThis2 : STATIC ? globalThis2[TARGET] : globalThis2[TARGET] && globalThis2[TARGET].prototype;
      var target = GLOBAL ? path : path[TARGET] || createNonEnumerableProperty(path, TARGET, {})[TARGET];
      var targetPrototype = target.prototype;
      var FORCED, USE_NATIVE, VIRTUAL_PROTOTYPE;
      var key, sourceProperty, targetProperty, nativeProperty, resultProperty, descriptor;
      for (key in source) {
        FORCED = isForced(GLOBAL ? key : TARGET + (STATIC ? "." : "#") + key, options.forced);
        USE_NATIVE = !FORCED && nativeSource && hasOwn(nativeSource, key);
        targetProperty = target[key];
        if (USE_NATIVE)
          if (options.dontCallGetSet) {
            descriptor = getOwnPropertyDescriptor(nativeSource, key);
            nativeProperty = descriptor && descriptor.value;
          } else
            nativeProperty = nativeSource[key];
        sourceProperty = USE_NATIVE && nativeProperty ? nativeProperty : source[key];
        if (!FORCED && !PROTO && typeof targetProperty == typeof sourceProperty)
          continue;
        if (options.bind && USE_NATIVE)
          resultProperty = bind(sourceProperty, globalThis2);
        else if (options.wrap && USE_NATIVE)
          resultProperty = wrapConstructor(sourceProperty);
        else if (PROTO && isCallable(sourceProperty))
          resultProperty = uncurryThis(sourceProperty);
        else
          resultProperty = sourceProperty;
        if (options.sham || sourceProperty && sourceProperty.sham || targetProperty && targetProperty.sham) {
          createNonEnumerableProperty(resultProperty, "sham", true);
        }
        createNonEnumerableProperty(target, key, resultProperty);
        if (PROTO) {
          VIRTUAL_PROTOTYPE = TARGET + "Prototype";
          if (!hasOwn(path, VIRTUAL_PROTOTYPE)) {
            createNonEnumerableProperty(path, VIRTUAL_PROTOTYPE, {});
          }
          createNonEnumerableProperty(path[VIRTUAL_PROTOTYPE], key, sourceProperty);
          if (options.real && targetPrototype && (FORCED || !targetPrototype[key])) {
            createNonEnumerableProperty(targetPrototype, key, sourceProperty);
          }
        }
      }
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-name.js
  var require_function_name = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var hasOwn = require_has_own_property();
    var FunctionPrototype = Function.prototype;
    var getDescriptor = DESCRIPTORS && Object.getOwnPropertyDescriptor;
    var EXISTS = hasOwn(FunctionPrototype, "name");
    var PROPER = EXISTS && function something() {}.name === "something";
    var CONFIGURABLE = EXISTS && (!DESCRIPTORS || DESCRIPTORS && getDescriptor(FunctionPrototype, "name").configurable);
    module.exports = {
      EXISTS,
      PROPER,
      CONFIGURABLE
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/math-trunc.js
  var require_math_trunc = __commonJS(function(exports, module) {
    var ceil = Math.ceil;
    var floor = Math.floor;
    module.exports = Math.trunc || function trunc(x) {
      var n = +x;
      return (n > 0 ? floor : ceil)(n);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-integer-or-infinity.js
  var require_to_integer_or_infinity = __commonJS(function(exports, module) {
    var trunc = require_math_trunc();
    module.exports = function(argument) {
      var number = +argument;
      return number !== number || number === 0 ? 0 : trunc(number);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-absolute-index.js
  var require_to_absolute_index = __commonJS(function(exports, module) {
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var max = Math.max;
    var min = Math.min;
    module.exports = function(index, length) {
      var integer = toIntegerOrInfinity(index);
      return integer < 0 ? max(integer + length, 0) : min(integer, length);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-length.js
  var require_to_length = __commonJS(function(exports, module) {
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var min = Math.min;
    module.exports = function(argument) {
      var len = toIntegerOrInfinity(argument);
      return len > 0 ? min(len, 9007199254740991) : 0;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/length-of-array-like.js
  var require_length_of_array_like = __commonJS(function(exports, module) {
    var toLength = require_to_length();
    module.exports = function(obj) {
      return toLength(obj.length);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/array-includes.js
  var require_array_includes = __commonJS(function(exports, module) {
    var toIndexedObject = require_to_indexed_object();
    var toAbsoluteIndex = require_to_absolute_index();
    var lengthOfArrayLike = require_length_of_array_like();
    var createMethod = function(IS_INCLUDES) {
      return function($this, el, fromIndex) {
        var O = toIndexedObject($this);
        var length = lengthOfArrayLike(O);
        if (length === 0)
          return !IS_INCLUDES && -1;
        var index = toAbsoluteIndex(fromIndex, length);
        var value;
        if (IS_INCLUDES && el !== el)
          while (length > index) {
            value = O[index++];
            if (value !== value)
              return true;
          }
        else
          for (;length > index; index++) {
            if ((IS_INCLUDES || (index in O)) && O[index] === el)
              return IS_INCLUDES || index || 0;
          }
        return !IS_INCLUDES && -1;
      };
    };
    module.exports = {
      includes: createMethod(true),
      indexOf: createMethod(false)
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-keys-internal.js
  var require_object_keys_internal = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var hasOwn = require_has_own_property();
    var toIndexedObject = require_to_indexed_object();
    var indexOf = require_array_includes().indexOf;
    var hiddenKeys = require_hidden_keys();
    var push = uncurryThis([].push);
    module.exports = function(object, names) {
      var O = toIndexedObject(object);
      var i = 0;
      var result = [];
      var key;
      for (key in O)
        !hasOwn(hiddenKeys, key) && hasOwn(O, key) && push(result, key);
      while (names.length > i)
        if (hasOwn(O, key = names[i++])) {
          ~indexOf(result, key) || push(result, key);
        }
      return result;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/enum-bug-keys.js
  var require_enum_bug_keys = __commonJS(function(exports, module) {
    module.exports = [
      "constructor",
      "hasOwnProperty",
      "isPrototypeOf",
      "propertyIsEnumerable",
      "toLocaleString",
      "toString",
      "valueOf"
    ];
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-keys.js
  var require_object_keys = __commonJS(function(exports, module) {
    var internalObjectKeys = require_object_keys_internal();
    var enumBugKeys = require_enum_bug_keys();
    module.exports = Object.keys || function keys(O) {
      return internalObjectKeys(O, enumBugKeys);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-define-properties.js
  var require_object_define_properties = __commonJS(function(exports) {
    var DESCRIPTORS = require_descriptors();
    var V8_PROTOTYPE_DEFINE_BUG = require_v8_prototype_define_bug();
    var definePropertyModule = require_object_define_property();
    var anObject = require_an_object();
    var toIndexedObject = require_to_indexed_object();
    var objectKeys = require_object_keys();
    exports.f = DESCRIPTORS && !V8_PROTOTYPE_DEFINE_BUG ? Object.defineProperties : function defineProperties(O, Properties) {
      anObject(O);
      var props = toIndexedObject(Properties);
      var keys = objectKeys(Properties);
      var length = keys.length;
      var index = 0;
      var key;
      while (length > index)
        definePropertyModule.f(O, key = keys[index++], props[key]);
      return O;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/html.js
  var require_html = __commonJS(function(exports, module) {
    var getBuiltIn = require_get_built_in();
    module.exports = getBuiltIn("document", "documentElement");
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-create.js
  var require_object_create = __commonJS(function(exports, module) {
    var anObject = require_an_object();
    var definePropertiesModule = require_object_define_properties();
    var enumBugKeys = require_enum_bug_keys();
    var hiddenKeys = require_hidden_keys();
    var html = require_html();
    var documentCreateElement = require_document_create_element();
    var sharedKey = require_shared_key();
    var GT = ">";
    var LT = "<";
    var PROTOTYPE = "prototype";
    var SCRIPT = "script";
    var IE_PROTO = sharedKey("IE_PROTO");
    var EmptyConstructor = function() {};
    var scriptTag = function(content) {
      return LT + SCRIPT + GT + content + LT + "/" + SCRIPT + GT;
    };
    var NullProtoObjectViaActiveX = function(activeXDocument) {
      activeXDocument.write(scriptTag(""));
      activeXDocument.close();
      var temp = activeXDocument.parentWindow.Object;
      activeXDocument = null;
      return temp;
    };
    var NullProtoObjectViaIFrame = function() {
      var iframe = documentCreateElement("iframe");
      var JS = "java" + SCRIPT + ":";
      var iframeDocument;
      iframe.style.display = "none";
      html.appendChild(iframe);
      iframe.src = String(JS);
      iframeDocument = iframe.contentWindow.document;
      iframeDocument.open();
      iframeDocument.write(scriptTag("document.F=Object"));
      iframeDocument.close();
      return iframeDocument.F;
    };
    var activeXDocument;
    var NullProtoObject = function() {
      try {
        activeXDocument = new ActiveXObject("htmlfile");
      } catch (error) {}
      NullProtoObject = typeof document != "undefined" ? document.domain && activeXDocument ? NullProtoObjectViaActiveX(activeXDocument) : NullProtoObjectViaIFrame() : NullProtoObjectViaActiveX(activeXDocument);
      var length = enumBugKeys.length;
      while (length--)
        delete NullProtoObject[PROTOTYPE][enumBugKeys[length]];
      return NullProtoObject();
    };
    hiddenKeys[IE_PROTO] = true;
    module.exports = Object.create || function create(O, Properties) {
      var result;
      if (O !== null) {
        EmptyConstructor[PROTOTYPE] = anObject(O);
        result = new EmptyConstructor;
        EmptyConstructor[PROTOTYPE] = null;
        result[IE_PROTO] = O;
      } else
        result = NullProtoObject();
      return Properties === undefined ? result : definePropertiesModule.f(result, Properties);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/correct-prototype-getter.js
  var require_correct_prototype_getter = __commonJS(function(exports, module) {
    var fails = require_fails();
    module.exports = !fails(function() {
      function F() {}
      F.prototype.constructor = null;
      return Object.getPrototypeOf(new F) !== F.prototype;
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-get-prototype-of.js
  var require_object_get_prototype_of = __commonJS(function(exports, module) {
    var hasOwn = require_has_own_property();
    var isCallable = require_is_callable();
    var toObject = require_to_object();
    var sharedKey = require_shared_key();
    var CORRECT_PROTOTYPE_GETTER = require_correct_prototype_getter();
    var IE_PROTO = sharedKey("IE_PROTO");
    var $Object = Object;
    var ObjectPrototype = $Object.prototype;
    module.exports = CORRECT_PROTOTYPE_GETTER ? $Object.getPrototypeOf : function(O) {
      var object = toObject(O);
      if (hasOwn(object, IE_PROTO))
        return object[IE_PROTO];
      var constructor = object.constructor;
      if (isCallable(constructor) && object instanceof constructor) {
        return constructor.prototype;
      }
      return object instanceof $Object ? ObjectPrototype : null;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/define-built-in.js
  var require_define_built_in = __commonJS(function(exports, module) {
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    module.exports = function(target, key, value, options) {
      if (options && options.enumerable)
        target[key] = value;
      else
        createNonEnumerableProperty(target, key, value);
      return target;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/iterators-core.js
  var require_iterators_core = __commonJS(function(exports, module) {
    var fails = require_fails();
    var isCallable = require_is_callable();
    var isObject = require_is_object();
    var create = require_object_create();
    var getPrototypeOf = require_object_get_prototype_of();
    var defineBuiltIn = require_define_built_in();
    var wellKnownSymbol = require_well_known_symbol();
    var IS_PURE = require_is_pure();
    var ITERATOR = wellKnownSymbol("iterator");
    var BUGGY_SAFARI_ITERATORS = false;
    var IteratorPrototype;
    var PrototypeOfArrayIteratorPrototype;
    var arrayIterator;
    if ([].keys) {
      arrayIterator = [].keys();
      if (!("next" in arrayIterator))
        BUGGY_SAFARI_ITERATORS = true;
      else {
        PrototypeOfArrayIteratorPrototype = getPrototypeOf(getPrototypeOf(arrayIterator));
        if (PrototypeOfArrayIteratorPrototype !== Object.prototype)
          IteratorPrototype = PrototypeOfArrayIteratorPrototype;
      }
    }
    var NEW_ITERATOR_PROTOTYPE = !isObject(IteratorPrototype) || fails(function() {
      var test = {};
      return IteratorPrototype[ITERATOR].call(test) !== test;
    });
    if (NEW_ITERATOR_PROTOTYPE)
      IteratorPrototype = {};
    else if (IS_PURE)
      IteratorPrototype = create(IteratorPrototype);
    if (!isCallable(IteratorPrototype[ITERATOR])) {
      defineBuiltIn(IteratorPrototype, ITERATOR, function() {
        return this;
      });
    }
    module.exports = {
      IteratorPrototype,
      BUGGY_SAFARI_ITERATORS
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-string-tag-support.js
  var require_to_string_tag_support = __commonJS(function(exports, module) {
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    var test = {};
    test[TO_STRING_TAG] = "z";
    module.exports = String(test) === "[object z]";
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/classof.js
  var require_classof = __commonJS(function(exports, module) {
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var isCallable = require_is_callable();
    var classofRaw = require_classof_raw();
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    var $Object = Object;
    var CORRECT_ARGUMENTS = classofRaw(function() {
      return arguments;
    }()) === "Arguments";
    var tryGet = function(it, key) {
      try {
        return it[key];
      } catch (error) {}
    };
    module.exports = TO_STRING_TAG_SUPPORT ? classofRaw : function(it) {
      var O, tag, result;
      return it === undefined ? "Undefined" : it === null ? "Null" : typeof (tag = tryGet(O = $Object(it), TO_STRING_TAG)) == "string" ? tag : CORRECT_ARGUMENTS ? classofRaw(O) : (result = classofRaw(O)) === "Object" && isCallable(O.callee) ? "Arguments" : result;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-to-string.js
  var require_object_to_string = __commonJS(function(exports, module) {
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var classof = require_classof();
    module.exports = TO_STRING_TAG_SUPPORT ? {}.toString : function toString() {
      return "[object " + classof(this) + "]";
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/set-to-string-tag.js
  var require_set_to_string_tag = __commonJS(function(exports, module) {
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var defineProperty = require_object_define_property().f;
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    var toString = require_object_to_string();
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    module.exports = function(it, TAG, STATIC, SET_METHOD) {
      var target = STATIC ? it : it && it.prototype;
      if (target) {
        if (!hasOwn(target, TO_STRING_TAG)) {
          defineProperty(target, TO_STRING_TAG, { configurable: true, value: TAG });
        }
        if (SET_METHOD && !TO_STRING_TAG_SUPPORT) {
          createNonEnumerableProperty(target, "toString", toString);
        }
      }
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/iterator-create-constructor.js
  var require_iterator_create_constructor = __commonJS(function(exports, module) {
    var IteratorPrototype = require_iterators_core().IteratorPrototype;
    var create = require_object_create();
    var createPropertyDescriptor = require_create_property_descriptor();
    var setToStringTag = require_set_to_string_tag();
    var Iterators = require_iterators();
    var returnThis = function() {
      return this;
    };
    module.exports = function(IteratorConstructor, NAME, next, ENUMERABLE_NEXT) {
      var TO_STRING_TAG = NAME + " Iterator";
      IteratorConstructor.prototype = create(IteratorPrototype, { next: createPropertyDescriptor(+!ENUMERABLE_NEXT, next) });
      setToStringTag(IteratorConstructor, TO_STRING_TAG, false, true);
      Iterators[TO_STRING_TAG] = returnThis;
      return IteratorConstructor;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/function-uncurry-this-accessor.js
  var require_function_uncurry_this_accessor = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var aCallable = require_a_callable();
    module.exports = function(object, key, method) {
      try {
        return uncurryThis(aCallable(Object.getOwnPropertyDescriptor(object, key)[method]));
      } catch (error) {}
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-possible-prototype.js
  var require_is_possible_prototype = __commonJS(function(exports, module) {
    var isObject = require_is_object();
    module.exports = function(argument) {
      return isObject(argument) || argument === null;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/a-possible-prototype.js
  var require_a_possible_prototype = __commonJS(function(exports, module) {
    var isPossiblePrototype = require_is_possible_prototype();
    var $String = String;
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isPossiblePrototype(argument))
        return argument;
      throw new $TypeError("Can't set " + $String(argument) + " as a prototype");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-set-prototype-of.js
  var require_object_set_prototype_of = __commonJS(function(exports, module) {
    var uncurryThisAccessor = require_function_uncurry_this_accessor();
    var isObject = require_is_object();
    var requireObjectCoercible = require_require_object_coercible();
    var aPossiblePrototype = require_a_possible_prototype();
    module.exports = Object.setPrototypeOf || ("__proto__" in {} ? function() {
      var CORRECT_SETTER = false;
      var test = {};
      var setter;
      try {
        setter = uncurryThisAccessor(Object.prototype, "__proto__", "set");
        setter(test, []);
        CORRECT_SETTER = test instanceof Array;
      } catch (error) {}
      return function setPrototypeOf(O, proto) {
        requireObjectCoercible(O);
        aPossiblePrototype(proto);
        if (!isObject(O))
          return O;
        if (CORRECT_SETTER)
          setter(O, proto);
        else
          O.__proto__ = proto;
        return O;
      };
    }() : undefined);
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/iterator-define.js
  var require_iterator_define = __commonJS(function(exports, module) {
    var $ = require_export();
    var call = require_function_call();
    var IS_PURE = require_is_pure();
    var FunctionName = require_function_name();
    var isCallable = require_is_callable();
    var createIteratorConstructor = require_iterator_create_constructor();
    var getPrototypeOf = require_object_get_prototype_of();
    var setPrototypeOf = require_object_set_prototype_of();
    var setToStringTag = require_set_to_string_tag();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var defineBuiltIn = require_define_built_in();
    var wellKnownSymbol = require_well_known_symbol();
    var Iterators = require_iterators();
    var IteratorsCore = require_iterators_core();
    var PROPER_FUNCTION_NAME = FunctionName.PROPER;
    var CONFIGURABLE_FUNCTION_NAME = FunctionName.CONFIGURABLE;
    var IteratorPrototype = IteratorsCore.IteratorPrototype;
    var BUGGY_SAFARI_ITERATORS = IteratorsCore.BUGGY_SAFARI_ITERATORS;
    var ITERATOR = wellKnownSymbol("iterator");
    var KEYS = "keys";
    var VALUES = "values";
    var ENTRIES = "entries";
    var returnThis = function() {
      return this;
    };
    module.exports = function(Iterable, NAME, IteratorConstructor, next, DEFAULT, IS_SET, FORCED) {
      createIteratorConstructor(IteratorConstructor, NAME, next);
      var getIterationMethod = function(KIND) {
        if (KIND === DEFAULT && defaultIterator)
          return defaultIterator;
        if (!BUGGY_SAFARI_ITERATORS && KIND && KIND in IterablePrototype)
          return IterablePrototype[KIND];
        switch (KIND) {
          case KEYS:
            return function keys() {
              return new IteratorConstructor(this, KIND);
            };
          case VALUES:
            return function values() {
              return new IteratorConstructor(this, KIND);
            };
          case ENTRIES:
            return function entries() {
              return new IteratorConstructor(this, KIND);
            };
        }
        return function() {
          return new IteratorConstructor(this);
        };
      };
      var TO_STRING_TAG = NAME + " Iterator";
      var INCORRECT_VALUES_NAME = false;
      var IterablePrototype = Iterable.prototype;
      var nativeIterator = IterablePrototype[ITERATOR] || IterablePrototype["@@iterator"] || DEFAULT && IterablePrototype[DEFAULT];
      var defaultIterator = !BUGGY_SAFARI_ITERATORS && nativeIterator || getIterationMethod(DEFAULT);
      var anyNativeIterator = NAME === "Array" ? IterablePrototype.entries || nativeIterator : nativeIterator;
      var CurrentIteratorPrototype, methods, KEY;
      if (anyNativeIterator) {
        CurrentIteratorPrototype = getPrototypeOf(anyNativeIterator.call(new Iterable));
        if (CurrentIteratorPrototype !== Object.prototype && CurrentIteratorPrototype.next) {
          if (!IS_PURE && getPrototypeOf(CurrentIteratorPrototype) !== IteratorPrototype) {
            if (setPrototypeOf) {
              setPrototypeOf(CurrentIteratorPrototype, IteratorPrototype);
            } else if (!isCallable(CurrentIteratorPrototype[ITERATOR])) {
              defineBuiltIn(CurrentIteratorPrototype, ITERATOR, returnThis);
            }
          }
          setToStringTag(CurrentIteratorPrototype, TO_STRING_TAG, true, true);
          if (IS_PURE)
            Iterators[TO_STRING_TAG] = returnThis;
        }
      }
      if (PROPER_FUNCTION_NAME && DEFAULT === VALUES && nativeIterator && nativeIterator.name !== VALUES) {
        if (!IS_PURE && CONFIGURABLE_FUNCTION_NAME) {
          createNonEnumerableProperty(IterablePrototype, "name", VALUES);
        } else {
          INCORRECT_VALUES_NAME = true;
          defaultIterator = function values() {
            return call(nativeIterator, this);
          };
        }
      }
      if (DEFAULT) {
        methods = {
          values: getIterationMethod(VALUES),
          keys: IS_SET ? defaultIterator : getIterationMethod(KEYS),
          entries: getIterationMethod(ENTRIES)
        };
        if (FORCED)
          for (KEY in methods) {
            if (BUGGY_SAFARI_ITERATORS || INCORRECT_VALUES_NAME || !(KEY in IterablePrototype)) {
              defineBuiltIn(IterablePrototype, KEY, methods[KEY]);
            }
          }
        else
          $({ target: NAME, proto: true, forced: BUGGY_SAFARI_ITERATORS || INCORRECT_VALUES_NAME }, methods);
      }
      if ((!IS_PURE || FORCED) && IterablePrototype[ITERATOR] !== defaultIterator) {
        defineBuiltIn(IterablePrototype, ITERATOR, defaultIterator, { name: DEFAULT });
      }
      Iterators[NAME] = defaultIterator;
      return methods;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/create-iter-result-object.js
  var require_create_iter_result_object = __commonJS(function(exports, module) {
    module.exports = function(value, done) {
      return { value, done };
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/es.array.iterator.js
  var require_es_array_iterator = __commonJS(function(exports, module) {
    var toIndexedObject = require_to_indexed_object();
    var addToUnscopables = require_add_to_unscopables();
    var Iterators = require_iterators();
    var InternalStateModule = require_internal_state();
    var defineProperty = require_object_define_property().f;
    var defineIterator = require_iterator_define();
    var createIterResultObject = require_create_iter_result_object();
    var IS_PURE = require_is_pure();
    var DESCRIPTORS = require_descriptors();
    var ARRAY_ITERATOR = "Array Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalState = InternalStateModule.getterFor(ARRAY_ITERATOR);
    module.exports = defineIterator(Array, "Array", function(iterated, kind) {
      setInternalState(this, {
        type: ARRAY_ITERATOR,
        target: toIndexedObject(iterated),
        index: 0,
        kind
      });
    }, function() {
      var state = getInternalState(this);
      var target = state.target;
      var index = state.index++;
      if (!target || index >= target.length) {
        state.target = null;
        return createIterResultObject(undefined, true);
      }
      switch (state.kind) {
        case "keys":
          return createIterResultObject(index, false);
        case "values":
          return createIterResultObject(target[index], false);
      }
      return createIterResultObject([index, target[index]], false);
    }, "values");
    var values = Iterators.Arguments = Iterators.Array;
    addToUnscopables("keys");
    addToUnscopables("values");
    addToUnscopables("entries");
    if (!IS_PURE && DESCRIPTORS && values.name !== "values")
      try {
        defineProperty(values, "name", { value: "values" });
      } catch (error) {}
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/safe-get-built-in.js
  var require_safe_get_built_in = __commonJS(function(exports, module) {
    var globalThis2 = require_global_this();
    var DESCRIPTORS = require_descriptors();
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    module.exports = function(name) {
      if (!DESCRIPTORS)
        return globalThis2[name];
      var descriptor = getOwnPropertyDescriptor(globalThis2, name);
      return descriptor && descriptor.value;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/url-constructor-detection.js
  var require_url_constructor_detection = __commonJS(function(exports, module) {
    var fails = require_fails();
    var wellKnownSymbol = require_well_known_symbol();
    var DESCRIPTORS = require_descriptors();
    var IS_PURE = require_is_pure();
    var ITERATOR = wellKnownSymbol("iterator");
    module.exports = !fails(function() {
      var url = new URL("b?a=1&b=2&c=3", "https://a");
      var params = url.searchParams;
      var params2 = new URLSearchParams("a=1&a=2&b=3");
      var result = "";
      url.pathname = "c%20d";
      params.forEach(function(value, key) {
        params["delete"]("b");
        result += key + value;
      });
      params2["delete"]("a", 2);
      params2["delete"]("b", undefined);
      return IS_PURE && (!url.toJSON || !params2.has("a", 1) || params2.has("a", 2) || !params2.has("a", undefined) || params2.has("b")) || !params.size && (IS_PURE || !DESCRIPTORS) || !params.sort || url.href !== "https://a/c%20d?a=1&c=3" || params.get("c") !== "3" || String(new URLSearchParams("?a=1")) !== "a=1" || !params[ITERATOR] || new URL("https://a@b").username !== "a" || new URLSearchParams(new URLSearchParams("a=b")).get("a") !== "b" || new URL("https://тест").host !== "xn--e1aybc" || new URL("https://a#б").hash !== "#%D0%B1" || result !== "a1c3" || new URL("https://x", undefined).host !== "x";
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/es.string.from-code-point.js
  var require_es_string_from_code_point = __commonJS(function() {
    var $ = require_export();
    var uncurryThis = require_function_uncurry_this();
    var toAbsoluteIndex = require_to_absolute_index();
    var $RangeError = RangeError;
    var fromCharCode = String.fromCharCode;
    var $fromCodePoint = String.fromCodePoint;
    var join = uncurryThis([].join);
    var INCORRECT_LENGTH = !!$fromCodePoint && $fromCodePoint.length !== 1;
    $({ target: "String", stat: true, arity: 1, forced: INCORRECT_LENGTH }, {
      fromCodePoint: function fromCodePoint(x) {
        var elements = [];
        var length = arguments.length;
        var i = 0;
        var code;
        while (length > i) {
          code = +arguments[i];
          if (toAbsoluteIndex(code, 1114111) !== code)
            throw new $RangeError(code + " is not a valid code point");
          elements[i++] = code < 65536 ? fromCharCode(code) : fromCharCode(((code -= 65536) >> 10) + 55296, code % 1024 + 56320);
        }
        return join(elements, "");
      }
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/url-percent-coding.js
  var require_url_percent_coding = __commonJS(function(exports, module) {
    require_es_string_from_code_point();
    var getBuiltIn = require_get_built_in();
    var uncurryThis = require_function_uncurry_this();
    var fromCharCode = String.fromCharCode;
    var fromCodePoint = getBuiltIn("String", "fromCodePoint");
    var $encodeURIComponent = encodeURIComponent;
    var $parseInt = parseInt;
    var charAt = uncurryThis("".charAt);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var stringSlice = uncurryThis("".slice);
    var exec = uncurryThis(/./.exec);
    var FALLBACK_REPLACER = "�";
    var VALID_HEX = /^[0-9a-f]+$/i;
    var SURROGATE = /[\uD800-\uDBFF][\uDC00-\uDFFF]|[\uD800-\uDFFF]/g;
    var parseHexOctet = function(string, start) {
      var substr = stringSlice(string, start, start + 2);
      if (!exec(VALID_HEX, substr))
        return NaN;
      return $parseInt(substr, 16);
    };
    var getLeadingOnes = function(octet) {
      var count = 0;
      for (var mask = 128;mask > 0 && (octet & mask) !== 0; mask >>= 1) {
        count++;
      }
      return count;
    };
    var utf8Decode = function(octets) {
      var codePoint = null;
      var length = octets.length;
      switch (length) {
        case 1:
          codePoint = octets[0];
          break;
        case 2:
          codePoint = (octets[0] & 31) << 6 | octets[1] & 63;
          break;
        case 3:
          codePoint = (octets[0] & 15) << 12 | (octets[1] & 63) << 6 | octets[2] & 63;
          break;
        case 4:
          codePoint = (octets[0] & 7) << 18 | (octets[1] & 63) << 12 | (octets[2] & 63) << 6 | octets[3] & 63;
          break;
      }
      if (codePoint === null || codePoint > 1114111 || codePoint >= 55296 && codePoint <= 57343 || codePoint < (length > 3 ? 65536 : length > 2 ? 2048 : length > 1 ? 128 : 0))
        return null;
      return codePoint;
    };
    var replaceLoneSurrogate = function(chunk) {
      return chunk.length === 2 ? chunk : FALLBACK_REPLACER;
    };
    var decode = function(input) {
      var length = input.length;
      var result = "";
      var i = 0;
      while (i < length) {
        var decodedChar = charAt(input, i);
        if (decodedChar === "%") {
          if (charAt(input, i + 1) === "%" || i + 3 > length) {
            result += "%";
            i++;
            continue;
          }
          var octet = parseHexOctet(input, i + 1);
          if (octet !== octet) {
            result += decodedChar;
            i++;
            continue;
          }
          i += 2;
          var byteSequenceLength = getLeadingOnes(octet);
          if (byteSequenceLength === 0) {
            decodedChar = fromCharCode(octet);
          } else {
            if (byteSequenceLength === 1 || byteSequenceLength > 4) {
              result += FALLBACK_REPLACER;
              i++;
              continue;
            }
            var octets = [octet];
            var sequenceIndex = 1;
            while (sequenceIndex < byteSequenceLength) {
              i++;
              if (i + 3 > length || charAt(input, i) !== "%")
                break;
              var nextByte = parseHexOctet(input, i + 1);
              if (nextByte !== nextByte || nextByte > 191 || nextByte < 128)
                break;
              if (sequenceIndex === 1) {
                if (octet === 224 && nextByte < 160)
                  break;
                if (octet === 237 && nextByte > 159)
                  break;
                if (octet === 240 && nextByte < 144)
                  break;
                if (octet === 244 && nextByte > 143)
                  break;
              }
              push(octets, nextByte);
              i += 2;
              sequenceIndex++;
            }
            if (octets.length !== byteSequenceLength) {
              result += FALLBACK_REPLACER;
              continue;
            }
            var codePoint = utf8Decode(octets);
            if (codePoint === null) {
              for (var replacement = 0;replacement < byteSequenceLength; replacement++)
                result += FALLBACK_REPLACER;
              i++;
              continue;
            } else {
              decodedChar = fromCodePoint(codePoint);
            }
          }
        }
        result += decodedChar;
        i++;
      }
      return result;
    };
    var encode = function(input) {
      try {
        return $encodeURIComponent(input);
      } catch (error) {
        return $encodeURIComponent(replace(input, SURROGATE, replaceLoneSurrogate));
      }
    };
    module.exports = {
      decode,
      encode
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/define-built-in-accessor.js
  var require_define_built_in_accessor = __commonJS(function(exports, module) {
    var defineProperty = require_object_define_property();
    module.exports = function(target, name, descriptor) {
      return defineProperty.f(target, name, descriptor);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/define-built-ins.js
  var require_define_built_ins = __commonJS(function(exports, module) {
    var defineBuiltIn = require_define_built_in();
    module.exports = function(target, src, options) {
      for (var key in src) {
        if (options && options.unsafe && target[key])
          target[key] = src[key];
        else
          defineBuiltIn(target, key, src[key], options);
      }
      return target;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/an-instance.js
  var require_an_instance = __commonJS(function(exports, module) {
    var isPrototypeOf = require_object_is_prototype_of();
    var $TypeError = TypeError;
    module.exports = function(it, Prototype) {
      if (isPrototypeOf(Prototype, it))
        return it;
      throw new $TypeError("Incorrect invocation");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/to-string.js
  var require_to_string = __commonJS(function(exports, module) {
    var classof = require_classof();
    var $String = String;
    module.exports = function(argument) {
      if (classof(argument) === "Symbol")
        throw new TypeError("Cannot convert a Symbol value to a string");
      return $String(argument);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/get-internal-iterator.js
  var require_get_internal_iterator = __commonJS(function(exports, module) {
    var classof = require_classof();
    var hasOwn = require_has_own_property();
    var Iterators = require_iterators();
    module.exports = function(it) {
      var klass = classof(it);
      if (klass === "Arguments")
        klass = "Array";
      return hasOwn(Iterators, klass) ? Iterators[klass] : undefined;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/get-iterator-method-internal.js
  var require_get_iterator_method_internal = __commonJS(function(exports, module) {
    var getMethod = require_get_method();
    var isNullOrUndefined = require_is_null_or_undefined();
    var getInternalIterator = require_get_internal_iterator();
    var wellKnownSymbol = require_well_known_symbol();
    var ITERATOR = wellKnownSymbol("iterator");
    module.exports = function(it) {
      if (!isNullOrUndefined(it))
        return getMethod(it, ITERATOR) || getMethod(it, "@@iterator") || getInternalIterator(it);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/get-iterator-internal.js
  var require_get_iterator_internal = __commonJS(function(exports, module) {
    var call = require_function_call();
    var isCallable = require_is_callable();
    var anObject = require_an_object();
    var tryToString = require_try_to_string();
    var getIteratorMethod = require_get_iterator_method_internal();
    var $TypeError = TypeError;
    module.exports = function(argument, usingIterator) {
      var iteratorMethod = arguments.length < 2 ? getIteratorMethod(argument) : usingIterator;
      if (isCallable(iteratorMethod))
        return anObject(call(iteratorMethod, argument));
      throw new $TypeError(tryToString(argument) + " is not iterable");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/validate-arguments-length.js
  var require_validate_arguments_length = __commonJS(function(exports, module) {
    var $TypeError = TypeError;
    module.exports = function(passed, required) {
      if (passed < required)
        throw new $TypeError("Not enough arguments");
      return passed;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/array-slice.js
  var require_array_slice = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    module.exports = uncurryThis([].slice);
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/array-sort.js
  var require_array_sort = __commonJS(function(exports, module) {
    var arraySlice = require_array_slice();
    var floor = Math.floor;
    var sort = function(array, comparefn) {
      var length = array.length;
      if (length < 8) {
        var i = 1;
        var element, j;
        while (i < length) {
          j = i;
          element = array[i];
          while (j && comparefn(array[j - 1], element) > 0) {
            array[j] = array[--j];
          }
          if (j !== i++)
            array[j] = element;
        }
      } else {
        var middle = floor(length / 2);
        var left = sort(arraySlice(array, 0, middle), comparefn);
        var right = sort(arraySlice(array, middle), comparefn);
        var llength = left.length;
        var rlength = right.length;
        var lindex = 0;
        var rindex = 0;
        while (lindex < llength || rindex < rlength) {
          array[lindex + rindex] = lindex < llength && rindex < rlength ? comparefn(left[lindex], right[rindex]) <= 0 ? left[lindex++] : right[rindex++] : lindex < llength ? left[lindex++] : right[rindex++];
        }
      }
      return array;
    };
    module.exports = sort;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url-search-params.constructor.js
  var require_web_url_search_params_constructor = __commonJS(function(exports, module) {
    require_es_array_iterator();
    var $ = require_export();
    var globalThis2 = require_global_this();
    var safeGetBuiltIn = require_safe_get_built_in();
    var call = require_function_call();
    var uncurryThis = require_function_uncurry_this();
    var DESCRIPTORS = require_descriptors();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var percentCoding = require_url_percent_coding();
    var defineBuiltIn = require_define_built_in();
    var defineBuiltInAccessor = require_define_built_in_accessor();
    var defineBuiltIns = require_define_built_ins();
    var setToStringTag = require_set_to_string_tag();
    var createIteratorConstructor = require_iterator_create_constructor();
    var InternalStateModule = require_internal_state();
    var anInstance = require_an_instance();
    var isCallable = require_is_callable();
    var hasOwn = require_has_own_property();
    var bind = require_function_bind_context();
    var classof = require_classof();
    var anObject = require_an_object();
    var isObject = require_is_object();
    var $toString = require_to_string();
    var create = require_object_create();
    var createPropertyDescriptor = require_create_property_descriptor();
    var getIterator = require_get_iterator_internal();
    var getIteratorMethod = require_get_iterator_method_internal();
    var createIterResultObject = require_create_iter_result_object();
    var validateArgumentsLength = require_validate_arguments_length();
    var wellKnownSymbol = require_well_known_symbol();
    var arraySort = require_array_sort();
    var ITERATOR = wellKnownSymbol("iterator");
    var URL_SEARCH_PARAMS = "URLSearchParams";
    var URL_SEARCH_PARAMS_ITERATOR = URL_SEARCH_PARAMS + "Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalParamsState = InternalStateModule.getterFor(URL_SEARCH_PARAMS);
    var getInternalIteratorState = InternalStateModule.getterFor(URL_SEARCH_PARAMS_ITERATOR);
    var percentDecode = percentCoding.decode;
    var percentEncode = percentCoding.encode;
    var nativeFetch = safeGetBuiltIn("fetch");
    var NativeRequest = safeGetBuiltIn("Request");
    var Headers2 = safeGetBuiltIn("Headers");
    var RequestPrototype = NativeRequest && NativeRequest.prototype;
    var HeadersPrototype = Headers2 && Headers2.prototype;
    var TypeError2 = globalThis2.TypeError;
    var charAt = uncurryThis("".charAt);
    var join = uncurryThis([].join);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var shift = uncurryThis([].shift);
    var splice = uncurryThis([].splice);
    var split = uncurryThis("".split);
    var stringSlice = uncurryThis("".slice);
    var plus = /\+/g;
    var decodeQueryComponent = function(input) {
      return percentDecode(replace(input, plus, " "));
    };
    var find = /[!'()~]|%20/g;
    var replacements = {
      "!": "%21",
      "'": "%27",
      "(": "%28",
      ")": "%29",
      "~": "%7E",
      "%20": "+"
    };
    var replacer = function(match) {
      return replacements[match];
    };
    var serialize = function(it) {
      return replace(percentEncode(it), find, replacer);
    };
    var URLSearchParamsIterator = createIteratorConstructor(function Iterator(params, kind) {
      setInternalState(this, {
        type: URL_SEARCH_PARAMS_ITERATOR,
        target: getInternalParamsState(params).entries,
        index: 0,
        kind
      });
    }, URL_SEARCH_PARAMS, function next() {
      var state = getInternalIteratorState(this);
      var target = state.target;
      var index = state.index++;
      if (!target || index >= target.length) {
        state.target = null;
        return createIterResultObject(undefined, true);
      }
      var entry = target[index];
      switch (state.kind) {
        case "keys":
          return createIterResultObject(entry.key, false);
        case "values":
          return createIterResultObject(entry.value, false);
      }
      return createIterResultObject([entry.key, entry.value], false);
    }, true);
    var URLSearchParamsState = function(init) {
      this.entries = [];
      this.url = null;
      if (init !== undefined) {
        if (isObject(init))
          this.parseObject(init);
        else
          this.parseQuery(typeof init == "string" ? charAt(init, 0) === "?" ? stringSlice(init, 1) : init : $toString(init));
      }
    };
    URLSearchParamsState.prototype = {
      type: URL_SEARCH_PARAMS,
      bindURL: function(url) {
        this.url = url;
        this.update();
      },
      parseObject: function(object) {
        var entries = this.entries;
        var iteratorMethod = getIteratorMethod(object);
        var iterator, next, step, entryIterator, entryNext, first, second;
        if (iteratorMethod) {
          iterator = getIterator(object, iteratorMethod);
          next = iterator.next;
          while (!(step = call(next, iterator)).done) {
            entryIterator = getIterator(anObject(step.value));
            entryNext = entryIterator.next;
            if ((first = call(entryNext, entryIterator)).done || (second = call(entryNext, entryIterator)).done || !call(entryNext, entryIterator).done)
              throw new TypeError2("Expected sequence with length 2");
            push(entries, { key: $toString(first.value), value: $toString(second.value) });
          }
        } else
          for (var key in object)
            if (hasOwn(object, key)) {
              push(entries, { key, value: $toString(object[key]) });
            }
      },
      parseQuery: function(query) {
        if (query) {
          var entries = this.entries;
          var attributes = split(query, "&");
          var index = 0;
          var attribute, entry;
          while (index < attributes.length) {
            attribute = attributes[index++];
            if (attribute.length) {
              entry = split(attribute, "=");
              push(entries, {
                key: decodeQueryComponent(shift(entry)),
                value: decodeQueryComponent(join(entry, "="))
              });
            }
          }
        }
      },
      serialize: function() {
        var entries = this.entries;
        var result = [];
        var index = 0;
        var entry;
        while (index < entries.length) {
          entry = entries[index++];
          push(result, serialize(entry.key) + "=" + serialize(entry.value));
        }
        return join(result, "&");
      },
      update: function() {
        this.entries.length = 0;
        this.parseQuery(this.url.query);
      },
      updateURL: function() {
        if (this.url)
          this.url.update();
      }
    };
    var URLSearchParamsConstructor = function URLSearchParams2() {
      anInstance(this, URLSearchParamsPrototype);
      var init = arguments.length > 0 ? arguments[0] : undefined;
      var state = setInternalState(this, new URLSearchParamsState(init));
      if (!DESCRIPTORS)
        this.size = state.entries.length;
    };
    var URLSearchParamsPrototype = URLSearchParamsConstructor.prototype;
    defineBuiltIns(URLSearchParamsPrototype, {
      append: function append(name, value) {
        var state = getInternalParamsState(this);
        validateArgumentsLength(arguments.length, 2);
        push(state.entries, { key: $toString(name), value: $toString(value) });
        if (!DESCRIPTORS)
          this.size++;
        state.updateURL();
      },
      delete: function(name) {
        var state = getInternalParamsState(this);
        var length = validateArgumentsLength(arguments.length, 1);
        var entries = state.entries;
        var key = $toString(name);
        var $value = length < 2 ? undefined : arguments[1];
        var value = $value === undefined ? $value : $toString($value);
        var index = 0;
        while (index < entries.length) {
          var entry = entries[index];
          if (entry.key === key && (value === undefined || entry.value === value)) {
            splice(entries, index, 1);
          } else
            index++;
        }
        if (!DESCRIPTORS)
          this.size = entries.length;
        state.updateURL();
      },
      get: function get(name) {
        var entries = getInternalParamsState(this).entries;
        validateArgumentsLength(arguments.length, 1);
        var key = $toString(name);
        var index = 0;
        for (;index < entries.length; index++) {
          if (entries[index].key === key)
            return entries[index].value;
        }
        return null;
      },
      getAll: function getAll(name) {
        var entries = getInternalParamsState(this).entries;
        validateArgumentsLength(arguments.length, 1);
        var key = $toString(name);
        var result = [];
        var index = 0;
        for (;index < entries.length; index++) {
          if (entries[index].key === key)
            push(result, entries[index].value);
        }
        return result;
      },
      has: function has(name) {
        var entries = getInternalParamsState(this).entries;
        var length = validateArgumentsLength(arguments.length, 1);
        var key = $toString(name);
        var $value = length < 2 ? undefined : arguments[1];
        var value = $value === undefined ? $value : $toString($value);
        var index = 0;
        while (index < entries.length) {
          var entry = entries[index++];
          if (entry.key === key && (value === undefined || entry.value === value))
            return true;
        }
        return false;
      },
      set: function set(name, value) {
        var state = getInternalParamsState(this);
        validateArgumentsLength(arguments.length, 2);
        var entries = state.entries;
        var found = false;
        var key = $toString(name);
        var val = $toString(value);
        var index = 0;
        var entry;
        for (;index < entries.length; index++) {
          entry = entries[index];
          if (entry.key === key) {
            if (found)
              splice(entries, index--, 1);
            else {
              found = true;
              entry.value = val;
            }
          }
        }
        if (!found)
          push(entries, { key, value: val });
        if (!DESCRIPTORS)
          this.size = entries.length;
        state.updateURL();
      },
      sort: function sort() {
        var state = getInternalParamsState(this);
        arraySort(state.entries, function(a, b) {
          return a.key > b.key ? 1 : -1;
        });
        state.updateURL();
      },
      forEach: function forEach(callback) {
        var entries = getInternalParamsState(this).entries;
        var boundFunction = bind(callback, arguments.length > 1 ? arguments[1] : undefined);
        var index = 0;
        var entry;
        while (index < entries.length) {
          entry = entries[index++];
          boundFunction(entry.value, entry.key, this);
        }
      },
      keys: function keys() {
        return new URLSearchParamsIterator(this, "keys");
      },
      values: function values() {
        return new URLSearchParamsIterator(this, "values");
      },
      entries: function entries() {
        return new URLSearchParamsIterator(this, "entries");
      }
    }, { enumerable: true });
    defineBuiltIn(URLSearchParamsPrototype, ITERATOR, URLSearchParamsPrototype.entries, { name: "entries" });
    defineBuiltIn(URLSearchParamsPrototype, "toString", function toString() {
      return getInternalParamsState(this).serialize();
    }, { enumerable: true });
    if (DESCRIPTORS)
      defineBuiltInAccessor(URLSearchParamsPrototype, "size", {
        get: function size() {
          return getInternalParamsState(this).entries.length;
        },
        configurable: true,
        enumerable: true
      });
    setToStringTag(URLSearchParamsConstructor, URL_SEARCH_PARAMS);
    $({ global: true, constructor: true, forced: !USE_NATIVE_URL }, {
      URLSearchParams: URLSearchParamsConstructor
    });
    if (!USE_NATIVE_URL && isCallable(Headers2)) {
      headersHas = uncurryThis(HeadersPrototype.has);
      headersSet = uncurryThis(HeadersPrototype.set);
      wrapRequestOptions = function(init) {
        if (isObject(init)) {
          var body = init.body;
          var headers;
          if (classof(body) === URL_SEARCH_PARAMS) {
            headers = init.headers ? new Headers2(init.headers) : new Headers2;
            if (!headersHas(headers, "content-type")) {
              headersSet(headers, "content-type", "application/x-www-form-urlencoded;charset=UTF-8");
            }
            return create(init, {
              body: createPropertyDescriptor(0, $toString(body)),
              headers: createPropertyDescriptor(0, headers)
            });
          }
        }
        return init;
      };
      if (isCallable(nativeFetch)) {
        $({ global: true, enumerable: true, dontCallGetSet: true, forced: true }, {
          fetch: function fetch2(input) {
            return nativeFetch(input, arguments.length > 1 ? wrapRequestOptions(arguments[1]) : {});
          }
        });
      }
      if (isCallable(NativeRequest)) {
        RequestConstructor = function Request(input) {
          anInstance(this, RequestPrototype);
          return new NativeRequest(input, arguments.length > 1 ? wrapRequestOptions(arguments[1]) : {});
        };
        RequestPrototype.constructor = RequestConstructor;
        RequestConstructor.prototype = RequestPrototype;
        $({ global: true, constructor: true, dontCallGetSet: true, forced: true }, {
          Request: RequestConstructor
        });
      }
    }
    var headersHas;
    var headersSet;
    var wrapRequestOptions;
    var RequestConstructor;
    module.exports = {
      URLSearchParams: URLSearchParamsConstructor,
      getState: getInternalParamsState
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url-search-params.js
  var require_web_url_search_params = __commonJS(function() {
    require_web_url_search_params_constructor();
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/web/url-search-params.js
  var require_url_search_params = __commonJS(function(exports, module) {
    require_web_url_search_params();
    ;
    ;
    ;
    var path = require_path();
    module.exports = path.URLSearchParams;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/string-multibyte.js
  var require_string_multibyte = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var toString = require_to_string();
    var requireObjectCoercible = require_require_object_coercible();
    var charAt = uncurryThis("".charAt);
    var charCodeAt = uncurryThis("".charCodeAt);
    var stringSlice = uncurryThis("".slice);
    var createMethod = function(CONVERT_TO_STRING) {
      return function($this, pos) {
        var S = toString(requireObjectCoercible($this));
        var position = toIntegerOrInfinity(pos);
        var size = S.length;
        var first, second;
        if (position < 0 || position >= size)
          return CONVERT_TO_STRING ? "" : undefined;
        first = charCodeAt(S, position);
        return first < 55296 || first > 56319 || position + 1 === size || (second = charCodeAt(S, position + 1)) < 56320 || second > 57343 ? CONVERT_TO_STRING ? charAt(S, position) : first : CONVERT_TO_STRING ? stringSlice(S, position, position + 2) : (first - 55296 << 10) + (second - 56320) + 65536;
      };
    };
    module.exports = {
      codeAt: createMethod(false),
      charAt: createMethod(true)
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/es.string.iterator.js
  var require_es_string_iterator = __commonJS(function() {
    var charAt = require_string_multibyte().charAt;
    var toString = require_to_string();
    var InternalStateModule = require_internal_state();
    var defineIterator = require_iterator_define();
    var createIterResultObject = require_create_iter_result_object();
    var STRING_ITERATOR = "String Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalState = InternalStateModule.getterFor(STRING_ITERATOR);
    defineIterator(String, "String", function(iterated) {
      setInternalState(this, {
        type: STRING_ITERATOR,
        string: toString(iterated),
        index: 0
      });
    }, function next() {
      var state = getInternalState(this);
      var string = state.string;
      var index = state.index;
      var point;
      if (index >= string.length)
        return createIterResultObject(undefined, true);
      point = charAt(string, index);
      state.index += point.length;
      return createIterResultObject(point, false);
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-get-own-property-symbols.js
  var require_object_get_own_property_symbols = __commonJS(function(exports) {
    exports.f = Object.getOwnPropertySymbols;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/object-assign.js
  var require_object_assign = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var uncurryThis = require_function_uncurry_this();
    var call = require_function_call();
    var fails = require_fails();
    var objectKeys = require_object_keys();
    var getOwnPropertySymbolsModule = require_object_get_own_property_symbols();
    var propertyIsEnumerableModule = require_object_property_is_enumerable();
    var toObject = require_to_object();
    var IndexedObject = require_indexed_object();
    var $assign = Object.assign;
    var defineProperty = Object.defineProperty;
    var concat = uncurryThis([].concat);
    module.exports = !$assign || fails(function() {
      if (DESCRIPTORS && $assign({ b: 1 }, $assign(defineProperty({}, "a", {
        enumerable: true,
        get: function() {
          defineProperty(this, "b", {
            value: 3,
            enumerable: false
          });
        }
      }), { b: 2 })).b !== 1)
        return true;
      var A = {};
      var B = {};
      var symbol = Symbol("assign detection");
      var alphabet = "abcdefghijklmnopqrst";
      A[symbol] = 7;
      alphabet.split("").forEach(function(chr) {
        B[chr] = chr;
      });
      return $assign({}, A)[symbol] !== 7 || objectKeys($assign({}, B)).join("") !== alphabet;
    }) ? function assign(target, source) {
      var T = toObject(target);
      var argumentsLength = arguments.length;
      var index = 1;
      var getOwnPropertySymbols = getOwnPropertySymbolsModule.f;
      var propertyIsEnumerable = propertyIsEnumerableModule.f;
      while (argumentsLength > index) {
        var S = IndexedObject(arguments[index++]);
        var keys = getOwnPropertySymbols ? concat(objectKeys(S), getOwnPropertySymbols(S)) : objectKeys(S);
        var length = keys.length;
        var j = 0;
        var key;
        while (length > j) {
          key = keys[j++];
          if (!DESCRIPTORS || call(propertyIsEnumerable, S, key))
            T[key] = S[key];
        }
      }
      return T;
    } : $assign;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/iterator-close.js
  var require_iterator_close = __commonJS(function(exports, module) {
    var call = require_function_call();
    var anObject = require_an_object();
    var getMethod = require_get_method();
    module.exports = function(iterator, kind, value) {
      var innerResult, innerError;
      anObject(iterator);
      try {
        innerResult = getMethod(iterator, "return");
        if (!innerResult) {
          if (kind === "throw")
            throw value;
          return value;
        }
        innerResult = call(innerResult, iterator);
      } catch (error) {
        innerError = true;
        innerResult = error;
      }
      if (kind === "throw")
        throw value;
      if (innerError)
        throw innerResult;
      anObject(innerResult);
      return value;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/call-with-safe-iteration-closing.js
  var require_call_with_safe_iteration_closing = __commonJS(function(exports, module) {
    var anObject = require_an_object();
    var iteratorClose = require_iterator_close();
    module.exports = function(iterator, fn, value, ENTRIES) {
      try {
        return ENTRIES ? fn(anObject(value)[0], value[1]) : fn(value);
      } catch (error) {
        iteratorClose(iterator, "throw", error);
      }
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-array-iterator-method.js
  var require_is_array_iterator_method = __commonJS(function(exports, module) {
    var wellKnownSymbol = require_well_known_symbol();
    var Iterators = require_iterators();
    var ITERATOR = wellKnownSymbol("iterator");
    var ArrayPrototype = Array.prototype;
    module.exports = function(it) {
      return it !== undefined && (Iterators.Array === it || ArrayPrototype[ITERATOR] === it);
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/inspect-source.js
  var require_inspect_source = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var isCallable = require_is_callable();
    var store = require_shared_store();
    var functionToString = uncurryThis(Function.toString);
    if (!isCallable(store.inspectSource)) {
      store.inspectSource = function(it) {
        return functionToString(it);
      };
    }
    module.exports = store.inspectSource;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-constructor.js
  var require_is_constructor = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var fails = require_fails();
    var isCallable = require_is_callable();
    var classof = require_classof();
    var getBuiltIn = require_get_built_in();
    var inspectSource = require_inspect_source();
    var noop = function() {};
    var construct = getBuiltIn("Reflect", "construct");
    var constructorRegExp = /^\s*(?:class|function)\b/;
    var exec = uncurryThis(constructorRegExp.exec);
    var INCORRECT_TO_STRING = !constructorRegExp.test(noop);
    var isConstructorModern = function isConstructor(argument) {
      if (!isCallable(argument))
        return false;
      try {
        construct(noop, [], argument);
        return true;
      } catch (error) {
        return false;
      }
    };
    var isConstructorLegacy = function isConstructor(argument) {
      if (!isCallable(argument))
        return false;
      switch (classof(argument)) {
        case "AsyncFunction":
        case "GeneratorFunction":
        case "AsyncGeneratorFunction":
          return false;
      }
      try {
        return INCORRECT_TO_STRING || !!exec(constructorRegExp, inspectSource(argument));
      } catch (error) {
        return true;
      }
    };
    isConstructorLegacy.sham = true;
    module.exports = !construct || fails(function() {
      var called;
      return isConstructorModern(isConstructorModern.call) || !isConstructorModern(Object) || !isConstructorModern(function() {
        called = true;
      }) || called;
    }) ? isConstructorLegacy : isConstructorModern;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/create-property.js
  var require_create_property = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var definePropertyModule = require_object_define_property();
    var createPropertyDescriptor = require_create_property_descriptor();
    module.exports = function(object, key, value) {
      if (DESCRIPTORS)
        definePropertyModule.f(object, key, createPropertyDescriptor(0, value));
      else
        object[key] = value;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/is-array.js
  var require_is_array = __commonJS(function(exports, module) {
    var classof = require_classof_raw();
    module.exports = Array.isArray || function isArray(argument) {
      return classof(argument) === "Array";
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/array-set-length.js
  var require_array_set_length = __commonJS(function(exports, module) {
    var DESCRIPTORS = require_descriptors();
    var isArray = require_is_array();
    var $TypeError = TypeError;
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var SILENT_ON_NON_WRITABLE_LENGTH_SET = DESCRIPTORS && !function() {
      if (this !== undefined)
        return true;
      try {
        Object.defineProperty([], "length", { writable: false }).length = 1;
      } catch (error) {
        return error instanceof TypeError;
      }
    }();
    module.exports = SILENT_ON_NON_WRITABLE_LENGTH_SET ? function(O, length) {
      if (isArray(O) && !getOwnPropertyDescriptor(O, "length").writable) {
        throw new $TypeError("Cannot set read only .length");
      }
      return O.length = length;
    } : function(O, length) {
      return O.length = length;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/does-not-exceed-safe-integer.js
  var require_does_not_exceed_safe_integer = __commonJS(function(exports, module) {
    var $TypeError = TypeError;
    var MAX_SAFE_INTEGER = 9007199254740991;
    module.exports = function(it) {
      if (it > MAX_SAFE_INTEGER)
        throw new $TypeError("Maximum allowed index exceeded");
      return it;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/array-from.js
  var require_array_from = __commonJS(function(exports, module) {
    var bind = require_function_bind_context();
    var call = require_function_call();
    var toObject = require_to_object();
    var callWithSafeIterationClosing = require_call_with_safe_iteration_closing();
    var isArrayIteratorMethod = require_is_array_iterator_method();
    var isConstructor = require_is_constructor();
    var lengthOfArrayLike = require_length_of_array_like();
    var createProperty = require_create_property();
    var setArrayLength = require_array_set_length();
    var getIterator = require_get_iterator_internal();
    var getIteratorMethod = require_get_iterator_method_internal();
    var iteratorClose = require_iterator_close();
    var doesNotExceedSafeInteger = require_does_not_exceed_safe_integer();
    var $Array = Array;
    module.exports = function from(arrayLike) {
      var IS_CONSTRUCTOR = isConstructor(this);
      var argumentsLength = arguments.length;
      var mapfn = argumentsLength > 1 ? arguments[1] : undefined;
      var mapping = mapfn !== undefined;
      if (mapping)
        mapfn = bind(mapfn, argumentsLength > 2 ? arguments[2] : undefined);
      var O = toObject(arrayLike);
      var iteratorMethod = getIteratorMethod(O);
      var index = 0;
      var length, result, step, iterator, next, value;
      if (iteratorMethod && !(this === $Array && isArrayIteratorMethod(iteratorMethod))) {
        result = IS_CONSTRUCTOR ? new this : [];
        iterator = getIterator(O, iteratorMethod);
        next = iterator.next;
        for (;!(step = call(next, iterator)).done; index++) {
          try {
            doesNotExceedSafeInteger(index);
          } catch (error) {
            iteratorClose(iterator, "throw", error);
          }
          value = mapping ? callWithSafeIterationClosing(iterator, mapfn, [step.value, index], true) : step.value;
          try {
            createProperty(result, index, value);
          } catch (error) {
            iteratorClose(iterator, "throw", error);
          }
        }
      } else {
        length = lengthOfArrayLike(O);
        result = IS_CONSTRUCTOR ? new this(length) : $Array(length);
        for (;length > index; index++) {
          value = mapping ? mapfn(O[index], index) : O[index];
          createProperty(result, index, value);
        }
      }
      setArrayLength(result, index);
      return result;
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/internals/string-punycode-to-ascii.js
  var require_string_punycode_to_ascii = __commonJS(function(exports, module) {
    var uncurryThis = require_function_uncurry_this();
    var maxInt = 2147483647;
    var base = 36;
    var tMin = 1;
    var tMax = 26;
    var skew = 38;
    var damp = 700;
    var initialBias = 72;
    var initialN = 128;
    var delimiter = "-";
    var regexNonASCII = /[^\0-\u007E]/;
    var regexSeparators = /[.\u3002\uFF0E\uFF61]/g;
    var OVERFLOW_ERROR = "Overflow: input needs wider integers to process";
    var baseMinusTMin = base - tMin;
    var $RangeError = RangeError;
    var exec = uncurryThis(regexSeparators.exec);
    var floor = Math.floor;
    var fromCharCode = String.fromCharCode;
    var charCodeAt = uncurryThis("".charCodeAt);
    var join = uncurryThis([].join);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var split = uncurryThis("".split);
    var toLowerCase = uncurryThis("".toLowerCase);
    var ucs2decode = function(string) {
      var output = [];
      var counter = 0;
      var length = string.length;
      while (counter < length) {
        var value = charCodeAt(string, counter++);
        if (value >= 55296 && value <= 56319 && counter < length) {
          var extra = charCodeAt(string, counter++);
          if ((extra & 64512) === 56320) {
            push(output, ((value & 1023) << 10) + (extra & 1023) + 65536);
          } else {
            push(output, value);
            counter--;
          }
        } else {
          push(output, value);
        }
      }
      return output;
    };
    var digitToBasic = function(digit) {
      return digit + 22 + 75 * (digit < 26);
    };
    var adapt = function(delta, numPoints, firstTime) {
      var k = 0;
      delta = firstTime ? floor(delta / damp) : delta >> 1;
      delta += floor(delta / numPoints);
      while (delta > baseMinusTMin * tMax >> 1) {
        delta = floor(delta / baseMinusTMin);
        k += base;
      }
      return floor(k + (baseMinusTMin + 1) * delta / (delta + skew));
    };
    var encode = function(input) {
      var output = [];
      input = ucs2decode(input);
      var inputLength = input.length;
      var n = initialN;
      var delta = 0;
      var bias = initialBias;
      var i, currentValue;
      for (i = 0;i < input.length; i++) {
        currentValue = input[i];
        if (currentValue < 128) {
          push(output, fromCharCode(currentValue));
        }
      }
      var basicLength = output.length;
      var handledCPCount = basicLength;
      if (basicLength) {
        push(output, delimiter);
      }
      while (handledCPCount < inputLength) {
        var m = maxInt;
        for (i = 0;i < input.length; i++) {
          currentValue = input[i];
          if (currentValue >= n && currentValue < m) {
            m = currentValue;
          }
        }
        var handledCPCountPlusOne = handledCPCount + 1;
        if (m - n > floor((maxInt - delta) / handledCPCountPlusOne)) {
          throw new $RangeError(OVERFLOW_ERROR);
        }
        delta += (m - n) * handledCPCountPlusOne;
        n = m;
        for (i = 0;i < input.length; i++) {
          currentValue = input[i];
          if (currentValue < n && ++delta > maxInt) {
            throw new $RangeError(OVERFLOW_ERROR);
          }
          if (currentValue === n) {
            var q = delta;
            var k = base;
            while (true) {
              var t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias;
              if (q < t)
                break;
              var qMinusT = q - t;
              var baseMinusT = base - t;
              push(output, fromCharCode(digitToBasic(t + qMinusT % baseMinusT)));
              q = floor(qMinusT / baseMinusT);
              k += base;
            }
            push(output, fromCharCode(digitToBasic(q)));
            bias = adapt(delta, handledCPCountPlusOne, handledCPCount === basicLength);
            delta = 0;
            handledCPCount++;
          }
        }
        delta++;
        n++;
      }
      return join(output, "");
    };
    module.exports = function(input) {
      var encoded = [];
      var labels = split(replace(toLowerCase(input), regexSeparators, "."), ".");
      var i, label;
      for (i = 0;i < labels.length; i++) {
        label = labels[i];
        push(encoded, exec(regexNonASCII, label) ? "xn--" + encode(label) : label);
      }
      return join(encoded, ".");
    };
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url.constructor.js
  var require_web_url_constructor = __commonJS(function() {
    require_es_string_iterator();
    var $ = require_export();
    var DESCRIPTORS = require_descriptors();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var globalThis2 = require_global_this();
    var bind = require_function_bind_context();
    var uncurryThis = require_function_uncurry_this();
    var defineBuiltIn = require_define_built_in();
    var defineBuiltInAccessor = require_define_built_in_accessor();
    var anInstance = require_an_instance();
    var hasOwn = require_has_own_property();
    var assign = require_object_assign();
    var arrayFrom = require_array_from();
    var arraySlice = require_array_slice();
    var codeAt = require_string_multibyte().codeAt;
    var toASCII = require_string_punycode_to_ascii();
    var percentCoding = require_url_percent_coding();
    var $toString = require_to_string();
    var setToStringTag = require_set_to_string_tag();
    var validateArgumentsLength = require_validate_arguments_length();
    var URLSearchParamsModule = require_web_url_search_params_constructor();
    var InternalStateModule = require_internal_state();
    var setInternalState = InternalStateModule.set;
    var getInternalURLState = InternalStateModule.getterFor("URL");
    var URLSearchParams2 = URLSearchParamsModule.URLSearchParams;
    var getInternalSearchParamsState = URLSearchParamsModule.getState;
    var percentDecode = percentCoding.decode;
    var percentEncode = percentCoding.encode;
    var NativeURL = globalThis2.URL;
    var TypeError2 = globalThis2.TypeError;
    var parseInt2 = globalThis2.parseInt;
    var floor = Math.floor;
    var pow = Math.pow;
    var fromCharCode = String.fromCharCode;
    var charAt = uncurryThis("".charAt);
    var exec = uncurryThis(/./.exec);
    var join = uncurryThis([].join);
    var numberToString = uncurryThis(1.1 .toString);
    var pop = uncurryThis([].pop);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var shift = uncurryThis([].shift);
    var split = uncurryThis("".split);
    var stringIndexOf = uncurryThis("".indexOf);
    var stringSlice = uncurryThis("".slice);
    var toLowerCase = uncurryThis("".toLowerCase);
    var unshift = uncurryThis([].unshift);
    var INVALID_AUTHORITY = "Invalid authority";
    var INVALID_SCHEME = "Invalid scheme";
    var INVALID_HOST = "Invalid host";
    var INVALID_PORT = "Invalid port";
    var ALPHA = /[a-z]/i;
    var ALPHANUMERIC_PLUS_MINUS_DOT = /[\d+\-.a-z]/i;
    var DIGIT = /\d/;
    var HEX_START = /^0x/i;
    var OCT = /^[0-7]+$/;
    var DEC = /^\d+$/;
    var HEX = /^[\da-f]+$/i;
    var FORBIDDEN_DOMAIN_CODE_POINT = /[\u0000-\u0020#%/:<>?@[\\\]^|\u007F]/;
    var FORBIDDEN_HOST_CODE_POINT = /[\0\t\n\r #/:<>?@[\\\]^|]/;
    var LEADING_C0_CONTROL_OR_SPACE = /^[\u0000-\u0020]+/;
    var TRAILING_C0_CONTROL_OR_SPACE = /(^|[^\u0000-\u0020])[\u0000-\u0020]+$/;
    var TAB_AND_NEW_LINE = /[\t\n\r]/g;
    var NON_ASCII = /[^\u0000-\u007F]/;
    var MAPPED_ONTO_FORBIDDEN = "¨¯´¸˘˙˚˛˜˝ͺ΄΅᾽᾿῀" + "῁῍῎῏῝῞῟῭΅´῾‗‾⁇⁈⁉" + "℀℁℅℆⩴゛゜ﱞﱟﱠﱡﱢﱣﷺﷻ︓" + "︖﹇﹈﹉﹊﹋﹌﹕﹖﹟﹤﹥﹨﹪﹫ﹰ" + "ﹲﹴﹶﹸﹺﹼﹾ￣";
    var EOF;
    var isIgnoredCodePoint = function(code) {
      return code === 173 || code === 847 || code === 8203 || code === 12644 || code === 65279 || code === 65440 || code >= 4447 && code <= 4448 || code >= 6068 && code <= 6069 || code >= 6155 && code <= 6159 || code >= 8288 && code <= 8292 || code >= 8298 && code <= 8303 || code >= 65024 && code <= 65039 || code >= 917760 && code <= 917999;
    };
    var isDisallowedCodePoint = function(code) {
      return code === 65533 || code >= 55296 && code <= 57343 || code >= 128 && code <= 159 || code >= 8206 && code <= 8207 || code >= 8232 && code <= 8233 || code >= 8234 && code <= 8238 || code >= 8293 && code <= 8297 || code >= 64976 && code <= 65007 || (code & 65534) === 65534 || code >= 57344 && code <= 63743 || code >= 983040 && code <= 1114109;
    };
    var mapCodePoint = function(code) {
      if (code >= 65281 && code <= 65374)
        return code - 65248;
      if (code === 160 || code === 5760 || code === 8239 || code === 8287 || code === 12288)
        return 32;
      if (code >= 8192 && code <= 8202)
        return 32;
      if (code <= 65535 && stringIndexOf(MAPPED_ONTO_FORBIDDEN, fromCharCode(code)) > -1)
        return 32;
      return code;
    };
    var domainToASCII = function(domain) {
      if (!exec(NON_ASCII, domain))
        return domain === "" ? null : toASCII(domain);
      var codePoints = arrayFrom(domain);
      var result = "";
      var index, code, mapped;
      for (index = 0;index < codePoints.length; index++) {
        code = codeAt(codePoints[index], 0);
        if (isDisallowedCodePoint(code))
          return null;
        if (isIgnoredCodePoint(code))
          continue;
        mapped = mapCodePoint(code);
        result += mapped === code ? codePoints[index] : fromCharCode(mapped);
      }
      return result === "" ? null : toASCII(result);
    };
    var endsInNumber = function(input) {
      var parts = split(input, ".");
      var last, hexPart;
      if (parts[parts.length - 1] === "") {
        if (parts.length === 1)
          return false;
        parts.length--;
      }
      last = parts[parts.length - 1];
      if (exec(DEC, last))
        return true;
      if (exec(HEX_START, last)) {
        hexPart = stringSlice(last, 2);
        return hexPart === "" || !!exec(HEX, hexPart);
      }
      return false;
    };
    var parseIPv4 = function(input) {
      var parts = split(input, ".");
      var partsLength, numbers, index, part, radix, number, ipv4;
      if (parts.length && parts[parts.length - 1] === "") {
        parts.length--;
      }
      partsLength = parts.length;
      if (partsLength > 4)
        return null;
      numbers = [];
      for (index = 0;index < partsLength; index++) {
        part = parts[index];
        if (part === "")
          return null;
        radix = 10;
        if (part.length > 1 && charAt(part, 0) === "0") {
          radix = exec(HEX_START, part) ? 16 : 8;
          part = stringSlice(part, radix === 8 ? 1 : 2);
        }
        if (part === "") {
          number = 0;
        } else {
          if (!exec(radix === 10 ? DEC : radix === 8 ? OCT : HEX, part))
            return null;
          number = parseInt2(part, radix);
        }
        push(numbers, number);
      }
      for (index = 0;index < partsLength; index++) {
        number = numbers[index];
        if (index === partsLength - 1) {
          if (number >= pow(256, 5 - partsLength))
            return null;
        } else if (number > 255)
          return null;
      }
      ipv4 = pop(numbers);
      for (index = 0;index < numbers.length; index++) {
        ipv4 += numbers[index] * pow(256, 3 - index);
      }
      return ipv4;
    };
    var parseIPv6 = function(input) {
      var address = [0, 0, 0, 0, 0, 0, 0, 0];
      var pieceIndex = 0;
      var compress = null;
      var pointer = 0;
      var value, length, numbersSeen, ipv4Piece, number, swaps, swap;
      var chr = function() {
        return charAt(input, pointer);
      };
      if (chr() === ":") {
        if (charAt(input, 1) !== ":")
          return;
        pointer += 2;
        pieceIndex++;
        compress = pieceIndex;
      }
      while (chr()) {
        if (pieceIndex === 8)
          return;
        if (chr() === ":") {
          if (compress !== null)
            return;
          pointer++;
          pieceIndex++;
          compress = pieceIndex;
          continue;
        }
        value = length = 0;
        while (length < 4 && exec(HEX, chr())) {
          value = value * 16 + parseInt2(chr(), 16);
          pointer++;
          length++;
        }
        if (chr() === ".") {
          if (length === 0)
            return;
          pointer -= length;
          if (pieceIndex > 6)
            return;
          numbersSeen = 0;
          while (chr()) {
            ipv4Piece = null;
            if (numbersSeen > 0) {
              if (chr() === "." && numbersSeen < 4)
                pointer++;
              else
                return;
            }
            if (!exec(DIGIT, chr()))
              return;
            while (exec(DIGIT, chr())) {
              number = parseInt2(chr(), 10);
              if (ipv4Piece === null)
                ipv4Piece = number;
              else if (ipv4Piece === 0)
                return;
              else
                ipv4Piece = ipv4Piece * 10 + number;
              if (ipv4Piece > 255)
                return;
              pointer++;
            }
            address[pieceIndex] = address[pieceIndex] * 256 + ipv4Piece;
            numbersSeen++;
            if (numbersSeen === 2 || numbersSeen === 4)
              pieceIndex++;
          }
          if (numbersSeen !== 4)
            return;
          break;
        } else if (chr() === ":") {
          pointer++;
          if (!chr())
            return;
        } else if (chr())
          return;
        address[pieceIndex++] = value;
      }
      if (compress !== null) {
        swaps = pieceIndex - compress;
        pieceIndex = 7;
        while (pieceIndex !== 0 && swaps > 0) {
          swap = address[pieceIndex];
          address[pieceIndex--] = address[compress + swaps - 1];
          address[compress + --swaps] = swap;
        }
      } else if (pieceIndex !== 8)
        return;
      return address;
    };
    var findLongestZeroSequence = function(ipv6) {
      var maxIndex = null;
      var maxLength = 1;
      var currStart = null;
      var currLength = 0;
      var index = 0;
      for (;index < 8; index++) {
        if (ipv6[index] !== 0) {
          if (currLength > maxLength) {
            maxIndex = currStart;
            maxLength = currLength;
          }
          currStart = null;
          currLength = 0;
        } else {
          if (currStart === null)
            currStart = index;
          ++currLength;
        }
      }
      return currLength > maxLength ? currStart : maxIndex;
    };
    var serializeHost = function(host) {
      var result, index, compress, ignore0;
      if (typeof host == "number") {
        result = [];
        for (index = 0;index < 4; index++) {
          unshift(result, host % 256);
          host = floor(host / 256);
        }
        return join(result, ".");
      }
      if (typeof host == "object") {
        result = "";
        compress = findLongestZeroSequence(host);
        for (index = 0;index < 8; index++) {
          if (ignore0 && host[index] === 0)
            continue;
          if (ignore0)
            ignore0 = false;
          if (compress === index) {
            result += index ? ":" : "::";
            ignore0 = true;
          } else {
            result += numberToString(host[index], 16);
            if (index < 7)
              result += ":";
          }
        }
        return "[" + result + "]";
      }
      return host;
    };
    var C0ControlPercentEncodeSet = {};
    var queryPercentEncodeSet = assign({}, C0ControlPercentEncodeSet, {
      " ": 1,
      '"': 1,
      "#": 1,
      "<": 1,
      ">": 1
    });
    var specialQueryPercentEncodeSet = assign({}, queryPercentEncodeSet, {
      "'": 1
    });
    var fragmentPercentEncodeSet = assign({}, C0ControlPercentEncodeSet, {
      " ": 1,
      '"': 1,
      "<": 1,
      ">": 1,
      "`": 1
    });
    var pathPercentEncodeSet = assign({}, fragmentPercentEncodeSet, {
      "#": 1,
      "?": 1,
      "{": 1,
      "}": 1,
      "^": 1
    });
    var userinfoPercentEncodeSet = assign({}, pathPercentEncodeSet, {
      "/": 1,
      ":": 1,
      ";": 1,
      "=": 1,
      "@": 1,
      "[": 1,
      "\\": 1,
      "]": 1,
      "^": 1,
      "|": 1
    });
    var utf8PercentEncode = function(chr, set) {
      var code = codeAt(chr, 0);
      return code >= 32 && code < 127 && !hasOwn(set, chr) ? chr : chr === "'" && hasOwn(set, chr) ? "%27" : percentEncode(chr);
    };
    var specialSchemes = {
      ftp: 21,
      file: null,
      http: 80,
      https: 443,
      ws: 80,
      wss: 443
    };
    var isWindowsDriveLetter = function(string, normalized) {
      var second;
      return string.length === 2 && exec(ALPHA, charAt(string, 0)) && ((second = charAt(string, 1)) === ":" || !normalized && second === "|");
    };
    var startsWithWindowsDriveLetter = function(string) {
      var third;
      return string.length > 1 && isWindowsDriveLetter(stringSlice(string, 0, 2)) && (string.length === 2 || ((third = charAt(string, 2)) === "/" || third === "\\" || third === "?" || third === "#"));
    };
    var isSingleDot = function(segment) {
      return segment === "." || toLowerCase(segment) === "%2e";
    };
    var isDoubleDot = function(segment) {
      segment = toLowerCase(segment);
      return segment === ".." || segment === "%2e." || segment === ".%2e" || segment === "%2e%2e";
    };
    var SCHEME_START = {};
    var SCHEME = {};
    var NO_SCHEME = {};
    var SPECIAL_RELATIVE_OR_AUTHORITY = {};
    var PATH_OR_AUTHORITY = {};
    var RELATIVE = {};
    var RELATIVE_SLASH = {};
    var SPECIAL_AUTHORITY_SLASHES = {};
    var SPECIAL_AUTHORITY_IGNORE_SLASHES = {};
    var AUTHORITY = {};
    var HOST = {};
    var HOSTNAME = {};
    var PORT = {};
    var FILE = {};
    var FILE_SLASH = {};
    var FILE_HOST = {};
    var PATH_START = {};
    var PATH = {};
    var CANNOT_BE_A_BASE_URL_PATH = {};
    var QUERY = {};
    var FRAGMENT = {};
    var URLState = function(url, isBase, base) {
      var urlString = $toString(url);
      var baseState, failure, searchParams;
      if (isBase) {
        failure = this.parse(urlString);
        if (failure)
          throw new TypeError2(failure);
        this.searchParams = null;
      } else {
        if (base !== undefined)
          baseState = new URLState(base, true);
        failure = this.parse(urlString, null, baseState);
        if (failure)
          throw new TypeError2(failure);
        searchParams = getInternalSearchParamsState(new URLSearchParams2);
        searchParams.bindURL(this);
        this.searchParams = searchParams;
      }
    };
    URLState.prototype = {
      type: "URL",
      parse: function(input, stateOverride, base) {
        var url = this;
        var state = stateOverride || SCHEME_START;
        var pointer = 0;
        var buffer = "";
        var seenAt = false;
        var seenBracket = false;
        var seenPasswordToken = false;
        var codePoints, chr, bufferCodePoints, failure;
        input = $toString(input);
        if (!stateOverride) {
          url.scheme = "";
          url.username = "";
          url.password = "";
          url.host = null;
          url.port = null;
          url.path = [];
          url.query = null;
          url.fragment = null;
          url.cannotBeABaseURL = false;
          input = replace(input, LEADING_C0_CONTROL_OR_SPACE, "");
          input = replace(input, TRAILING_C0_CONTROL_OR_SPACE, "$1");
        }
        input = replace(input, TAB_AND_NEW_LINE, "");
        codePoints = arrayFrom(input);
        while (pointer <= codePoints.length) {
          chr = codePoints[pointer];
          switch (state) {
            case SCHEME_START:
              if (chr && exec(ALPHA, chr)) {
                buffer += toLowerCase(chr);
                state = SCHEME;
              } else if (!stateOverride) {
                state = NO_SCHEME;
                continue;
              } else
                return INVALID_SCHEME;
              break;
            case SCHEME:
              if (chr && exec(ALPHANUMERIC_PLUS_MINUS_DOT, chr)) {
                buffer += toLowerCase(chr);
              } else if (chr === ":") {
                if (stateOverride && (url.isSpecial() !== hasOwn(specialSchemes, buffer) || buffer === "file" && (url.includesCredentials() || url.port !== null) || url.scheme === "file" && url.host === ""))
                  return;
                url.scheme = buffer;
                if (stateOverride) {
                  if (url.isSpecial() && specialSchemes[url.scheme] === url.port)
                    url.port = null;
                  return;
                }
                buffer = "";
                if (url.scheme === "file") {
                  state = FILE;
                } else if (url.isSpecial() && base && base.scheme === url.scheme) {
                  state = SPECIAL_RELATIVE_OR_AUTHORITY;
                } else if (url.isSpecial()) {
                  state = SPECIAL_AUTHORITY_SLASHES;
                } else if (codePoints[pointer + 1] === "/") {
                  state = PATH_OR_AUTHORITY;
                  pointer++;
                } else {
                  url.cannotBeABaseURL = true;
                  push(url.path, "");
                  state = CANNOT_BE_A_BASE_URL_PATH;
                }
              } else if (!stateOverride) {
                buffer = "";
                state = NO_SCHEME;
                pointer = 0;
                continue;
              } else
                return INVALID_SCHEME;
              break;
            case NO_SCHEME:
              if (!base || base.cannotBeABaseURL && chr !== "#")
                return INVALID_SCHEME;
              if (base.cannotBeABaseURL && chr === "#") {
                url.scheme = base.scheme;
                url.path = arraySlice(base.path);
                url.query = base.query;
                url.fragment = "";
                url.cannotBeABaseURL = true;
                state = FRAGMENT;
                break;
              }
              state = base.scheme === "file" ? FILE : RELATIVE;
              continue;
            case SPECIAL_RELATIVE_OR_AUTHORITY:
              if (chr === "/" && codePoints[pointer + 1] === "/") {
                state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
                pointer++;
              } else {
                state = RELATIVE;
                continue;
              }
              break;
            case PATH_OR_AUTHORITY:
              if (chr === "/") {
                state = AUTHORITY;
                break;
              } else {
                state = PATH;
                continue;
              }
            case RELATIVE:
              url.scheme = base.scheme;
              if (chr === EOF) {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = base.query;
              } else if (chr === "/" || chr === "\\" && url.isSpecial()) {
                state = RELATIVE_SLASH;
              } else if (chr === "?") {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = "";
                state = QUERY;
              } else if (chr === "#") {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = base.query;
                url.fragment = "";
                state = FRAGMENT;
              } else {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                if (url.path.length)
                  url.path.length--;
                state = PATH;
                continue;
              }
              break;
            case RELATIVE_SLASH:
              if (url.isSpecial() && (chr === "/" || chr === "\\")) {
                state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
              } else if (chr === "/") {
                state = AUTHORITY;
              } else {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                state = PATH;
                continue;
              }
              break;
            case SPECIAL_AUTHORITY_SLASHES:
              state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
              if (chr !== "/" || codePoints[pointer + 1] !== "/")
                continue;
              pointer++;
              break;
            case SPECIAL_AUTHORITY_IGNORE_SLASHES:
              if (chr !== "/" && chr !== "\\") {
                state = AUTHORITY;
                continue;
              }
              break;
            case AUTHORITY:
              if (chr === "@") {
                if (seenAt)
                  buffer = "%40" + buffer;
                seenAt = true;
                bufferCodePoints = arrayFrom(buffer);
                for (var i = 0;i < bufferCodePoints.length; i++) {
                  var codePoint = bufferCodePoints[i];
                  if (codePoint === ":" && !seenPasswordToken) {
                    seenPasswordToken = true;
                    continue;
                  }
                  var encodedCodePoints = utf8PercentEncode(codePoint, userinfoPercentEncodeSet);
                  if (seenPasswordToken)
                    url.password += encodedCodePoints;
                  else
                    url.username += encodedCodePoints;
                }
                buffer = "";
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial()) {
                if (seenAt && buffer === "")
                  return INVALID_AUTHORITY;
                pointer -= arrayFrom(buffer).length + 1;
                buffer = "";
                state = HOST;
              } else
                buffer += chr;
              break;
            case HOST:
            case HOSTNAME:
              if (stateOverride && url.scheme === "file") {
                state = FILE_HOST;
                continue;
              } else if (chr === ":" && !seenBracket) {
                if (buffer === "")
                  return INVALID_HOST;
                if (stateOverride === HOSTNAME)
                  return;
                failure = url.parseHost(buffer);
                if (failure)
                  return failure;
                buffer = "";
                state = PORT;
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial()) {
                if (url.isSpecial() && buffer === "")
                  return INVALID_HOST;
                if (stateOverride && buffer === "" && (url.includesCredentials() || url.port !== null))
                  return;
                failure = url.parseHost(buffer);
                if (failure)
                  return failure;
                buffer = "";
                state = PATH_START;
                if (stateOverride)
                  return;
                continue;
              } else {
                if (chr === "[")
                  seenBracket = true;
                else if (chr === "]")
                  seenBracket = false;
                buffer += chr;
              }
              break;
            case PORT:
              if (exec(DIGIT, chr)) {
                buffer += chr;
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial() || stateOverride) {
                if (buffer !== "") {
                  var port = parseInt2(buffer, 10);
                  if (port > 65535)
                    return INVALID_PORT;
                  url.port = url.isSpecial() && port === specialSchemes[url.scheme] ? null : port;
                  buffer = "";
                }
                if (stateOverride)
                  return;
                state = PATH_START;
                continue;
              } else
                return INVALID_PORT;
              break;
            case FILE:
              url.scheme = "file";
              url.host = "";
              if (chr === "/" || chr === "\\")
                state = FILE_SLASH;
              else if (base && base.scheme === "file") {
                switch (chr) {
                  case EOF:
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = base.query;
                    break;
                  case "?":
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = "";
                    state = QUERY;
                    break;
                  case "#":
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = base.query;
                    url.fragment = "";
                    state = FRAGMENT;
                    break;
                  default:
                    url.host = base.host;
                    if (!startsWithWindowsDriveLetter(join(arraySlice(codePoints, pointer), ""))) {
                      url.path = arraySlice(base.path);
                      url.shortenPath();
                    }
                    state = PATH;
                    continue;
                }
              } else {
                state = PATH;
                continue;
              }
              break;
            case FILE_SLASH:
              if (chr === "/" || chr === "\\") {
                state = FILE_HOST;
                break;
              }
              if (base && base.scheme === "file") {
                url.host = base.host;
                if (!startsWithWindowsDriveLetter(join(arraySlice(codePoints, pointer), "")) && isWindowsDriveLetter(base.path[0], true))
                  push(url.path, base.path[0]);
              }
              state = PATH;
              continue;
            case FILE_HOST:
              if (chr === EOF || chr === "/" || chr === "\\" || chr === "?" || chr === "#") {
                if (!stateOverride && isWindowsDriveLetter(buffer)) {
                  state = PATH;
                } else if (buffer === "") {
                  url.host = "";
                  if (stateOverride)
                    return;
                  state = PATH_START;
                } else {
                  failure = url.parseHost(buffer);
                  if (failure)
                    return failure;
                  if (url.host === "localhost")
                    url.host = "";
                  if (stateOverride)
                    return;
                  buffer = "";
                  state = PATH_START;
                }
                continue;
              } else
                buffer += chr;
              break;
            case PATH_START:
              if (url.isSpecial()) {
                state = PATH;
                if (chr !== "/" && chr !== "\\")
                  continue;
              } else if (!stateOverride && chr === "?") {
                url.query = "";
                state = QUERY;
              } else if (!stateOverride && chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                state = PATH;
                if (chr !== "/")
                  continue;
              }
              break;
            case PATH:
              if (chr === EOF || chr === "/" || chr === "\\" && url.isSpecial() || !stateOverride && (chr === "?" || chr === "#")) {
                if (isDoubleDot(buffer)) {
                  url.shortenPath();
                  if (chr !== "/" && !(chr === "\\" && url.isSpecial())) {
                    push(url.path, "");
                  }
                } else if (isSingleDot(buffer)) {
                  if (chr !== "/" && !(chr === "\\" && url.isSpecial())) {
                    push(url.path, "");
                  }
                } else {
                  if (url.scheme === "file" && !url.path.length && isWindowsDriveLetter(buffer)) {
                    if (url.host !== null && url.host !== "")
                      url.host = "";
                    buffer = charAt(buffer, 0) + ":";
                  }
                  push(url.path, buffer);
                }
                buffer = "";
                if (url.scheme === "file" && (chr === EOF || chr === "?" || chr === "#")) {
                  while (url.path.length > 1 && url.path[0] === "") {
                    shift(url.path);
                  }
                }
                if (chr === "?") {
                  url.query = "";
                  state = QUERY;
                } else if (chr === "#") {
                  url.fragment = "";
                  state = FRAGMENT;
                }
              } else {
                buffer += utf8PercentEncode(chr, pathPercentEncodeSet);
              }
              break;
            case CANNOT_BE_A_BASE_URL_PATH:
              if (chr === "?") {
                url.query = "";
                state = QUERY;
              } else if (chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                if (chr === " ") {
                  url.path[0] += codePoints[pointer + 1] === "?" || codePoints[pointer + 1] === "#" ? "%20" : " ";
                } else {
                  url.path[0] += utf8PercentEncode(chr, C0ControlPercentEncodeSet);
                }
              }
              break;
            case QUERY:
              if (!stateOverride && chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                url.query += utf8PercentEncode(chr, url.isSpecial() ? specialQueryPercentEncodeSet : queryPercentEncodeSet);
              }
              break;
            case FRAGMENT:
              if (chr !== EOF)
                url.fragment += utf8PercentEncode(chr, fragmentPercentEncodeSet);
              break;
          }
          pointer++;
        }
      },
      parseHost: function(input) {
        var result, codePoints, index;
        if (charAt(input, 0) === "[") {
          if (charAt(input, input.length - 1) !== "]")
            return INVALID_HOST;
          result = parseIPv6(stringSlice(input, 1, -1));
          if (!result)
            return INVALID_HOST;
          this.host = result;
        } else if (!this.isSpecial()) {
          if (exec(FORBIDDEN_HOST_CODE_POINT, input))
            return INVALID_HOST;
          result = "";
          codePoints = arrayFrom(input);
          for (index = 0;index < codePoints.length; index++) {
            result += utf8PercentEncode(codePoints[index], C0ControlPercentEncodeSet);
          }
          this.host = result;
        } else {
          input = domainToASCII(percentDecode(input));
          if (input === null || exec(FORBIDDEN_DOMAIN_CODE_POINT, input))
            return INVALID_HOST;
          if (endsInNumber(input)) {
            result = parseIPv4(input);
            if (result === null)
              return INVALID_HOST;
            this.host = result;
          } else {
            this.host = input;
          }
        }
      },
      cannotHaveUsernamePasswordPort: function() {
        return this.host === null || this.host === "" || this.cannotBeABaseURL || this.scheme === "file";
      },
      includesCredentials: function() {
        return this.username !== "" || this.password !== "";
      },
      isSpecial: function() {
        return hasOwn(specialSchemes, this.scheme);
      },
      shortenPath: function() {
        var path = this.path;
        var pathSize = path.length;
        if (pathSize && (this.scheme !== "file" || pathSize !== 1 || !isWindowsDriveLetter(path[0], true))) {
          path.length--;
        }
      },
      serialize: function() {
        var url = this;
        var scheme = url.scheme;
        var username = url.username;
        var password = url.password;
        var host = url.host;
        var port = url.port;
        var path = url.path;
        var query = url.query;
        var fragment = url.fragment;
        var output = scheme + ":";
        if (host !== null) {
          output += "//";
          if (url.includesCredentials()) {
            output += username + (password ? ":" + password : "") + "@";
          }
          output += serializeHost(host);
          if (port !== null)
            output += ":" + port;
        } else if (scheme === "file")
          output += "//";
        if (host === null && !url.cannotBeABaseURL && path.length > 1 && path[0] === "")
          output += "/.";
        output += url.cannotBeABaseURL ? path[0] : path.length ? "/" + join(path, "/") : "";
        if (query !== null)
          output += "?" + query;
        if (fragment !== null)
          output += "#" + fragment;
        return output;
      },
      setHref: function(href) {
        var failure = this.parse(href);
        if (failure)
          throw new TypeError2(failure);
        this.searchParams.update();
      },
      getOrigin: function() {
        var scheme = this.scheme;
        var port = this.port;
        if (scheme === "blob")
          try {
            return new URLConstructor(this.path[0]).origin;
          } catch (error) {
            return "null";
          }
        if (scheme === "file" || !this.isSpecial())
          return "null";
        return scheme + "://" + serializeHost(this.host) + (port !== null ? ":" + port : "");
      },
      getProtocol: function() {
        return this.scheme + ":";
      },
      setProtocol: function(protocol) {
        this.parse($toString(protocol) + ":", SCHEME_START);
      },
      getUsername: function() {
        return this.username;
      },
      setUsername: function(username) {
        var codePoints = arrayFrom($toString(username));
        if (this.cannotHaveUsernamePasswordPort())
          return;
        this.username = "";
        for (var i = 0;i < codePoints.length; i++) {
          this.username += utf8PercentEncode(codePoints[i], userinfoPercentEncodeSet);
        }
      },
      getPassword: function() {
        return this.password;
      },
      setPassword: function(password) {
        var codePoints = arrayFrom($toString(password));
        if (this.cannotHaveUsernamePasswordPort())
          return;
        this.password = "";
        for (var i = 0;i < codePoints.length; i++) {
          this.password += utf8PercentEncode(codePoints[i], userinfoPercentEncodeSet);
        }
      },
      getHost: function() {
        var host = this.host;
        var port = this.port;
        return host === null ? "" : port === null ? serializeHost(host) : serializeHost(host) + ":" + port;
      },
      setHost: function(host) {
        if (this.cannotBeABaseURL)
          return;
        this.parse(host, HOST);
      },
      getHostname: function() {
        var host = this.host;
        return host === null ? "" : serializeHost(host);
      },
      setHostname: function(hostname) {
        if (this.cannotBeABaseURL)
          return;
        this.parse(hostname, HOSTNAME);
      },
      getPort: function() {
        var port = this.port;
        return port === null ? "" : $toString(port);
      },
      setPort: function(port) {
        if (this.cannotHaveUsernamePasswordPort())
          return;
        port = $toString(port);
        if (port === "")
          this.port = null;
        else
          this.parse(port, PORT);
      },
      getPathname: function() {
        var path = this.path;
        return this.cannotBeABaseURL ? path[0] : path.length ? "/" + join(path, "/") : "";
      },
      setPathname: function(pathname) {
        if (this.cannotBeABaseURL)
          return;
        this.path = [];
        this.parse(pathname, PATH_START);
      },
      getSearch: function() {
        var query = this.query;
        return query ? "?" + query : "";
      },
      setSearch: function(search) {
        search = $toString(search);
        if (search === "") {
          this.query = null;
        } else {
          if (charAt(search, 0) === "?")
            search = stringSlice(search, 1);
          this.query = "";
          this.parse(search, QUERY);
        }
        this.searchParams.update();
      },
      getSearchParams: function() {
        return this.searchParams.facade;
      },
      getHash: function() {
        var fragment = this.fragment;
        return fragment ? "#" + fragment : "";
      },
      setHash: function(hash) {
        hash = $toString(hash);
        if (hash === "") {
          this.fragment = null;
          return;
        }
        if (charAt(hash, 0) === "#")
          hash = stringSlice(hash, 1);
        this.fragment = "";
        this.parse(hash, FRAGMENT);
      },
      update: function() {
        this.query = this.searchParams.serialize() || null;
      }
    };
    var URLConstructor = function URL2(url) {
      var that = anInstance(this, URLPrototype);
      var base = validateArgumentsLength(arguments.length, 1) > 1 ? arguments[1] : undefined;
      var state = setInternalState(that, new URLState(url, false, base));
      if (!DESCRIPTORS) {
        that.href = state.serialize();
        that.origin = state.getOrigin();
        that.protocol = state.getProtocol();
        that.username = state.getUsername();
        that.password = state.getPassword();
        that.host = state.getHost();
        that.hostname = state.getHostname();
        that.port = state.getPort();
        that.pathname = state.getPathname();
        that.search = state.getSearch();
        that.searchParams = state.getSearchParams();
        that.hash = state.getHash();
      }
    };
    var URLPrototype = URLConstructor.prototype;
    var accessorDescriptor = function(getter, setter) {
      return {
        get: function() {
          return getInternalURLState(this)[getter]();
        },
        set: setter && function(value) {
          return getInternalURLState(this)[setter](value);
        },
        configurable: true,
        enumerable: true
      };
    };
    if (DESCRIPTORS) {
      defineBuiltInAccessor(URLPrototype, "href", accessorDescriptor("serialize", "setHref"));
      defineBuiltInAccessor(URLPrototype, "origin", accessorDescriptor("getOrigin"));
      defineBuiltInAccessor(URLPrototype, "protocol", accessorDescriptor("getProtocol", "setProtocol"));
      defineBuiltInAccessor(URLPrototype, "username", accessorDescriptor("getUsername", "setUsername"));
      defineBuiltInAccessor(URLPrototype, "password", accessorDescriptor("getPassword", "setPassword"));
      defineBuiltInAccessor(URLPrototype, "host", accessorDescriptor("getHost", "setHost"));
      defineBuiltInAccessor(URLPrototype, "hostname", accessorDescriptor("getHostname", "setHostname"));
      defineBuiltInAccessor(URLPrototype, "port", accessorDescriptor("getPort", "setPort"));
      defineBuiltInAccessor(URLPrototype, "pathname", accessorDescriptor("getPathname", "setPathname"));
      defineBuiltInAccessor(URLPrototype, "search", accessorDescriptor("getSearch", "setSearch"));
      defineBuiltInAccessor(URLPrototype, "searchParams", accessorDescriptor("getSearchParams"));
      defineBuiltInAccessor(URLPrototype, "hash", accessorDescriptor("getHash", "setHash"));
    }
    defineBuiltIn(URLPrototype, "toJSON", function toJSON() {
      return getInternalURLState(this).serialize();
    }, { enumerable: true });
    defineBuiltIn(URLPrototype, "toString", function toString() {
      return getInternalURLState(this).serialize();
    }, { enumerable: true });
    if (NativeURL) {
      nativeCreateObjectURL = NativeURL.createObjectURL;
      nativeRevokeObjectURL = NativeURL.revokeObjectURL;
      if (nativeCreateObjectURL)
        defineBuiltIn(URLConstructor, "createObjectURL", bind(nativeCreateObjectURL, NativeURL));
      if (nativeRevokeObjectURL)
        defineBuiltIn(URLConstructor, "revokeObjectURL", bind(nativeRevokeObjectURL, NativeURL));
    }
    var nativeCreateObjectURL;
    var nativeRevokeObjectURL;
    setToStringTag(URLConstructor, "URL");
    $({ global: true, constructor: true, forced: !USE_NATIVE_URL, sham: !DESCRIPTORS }, {
      URL: URLConstructor
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url.js
  var require_web_url = __commonJS(function() {
    require_web_url_constructor();
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url.can-parse.js
  var require_web_url_can_parse = __commonJS(function() {
    var $ = require_export();
    var getBuiltIn = require_get_built_in();
    var fails = require_fails();
    var validateArgumentsLength = require_validate_arguments_length();
    var toString = require_to_string();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var URL2 = getBuiltIn("URL");
    var THROWS_WITHOUT_ARGUMENTS = USE_NATIVE_URL && fails(function() {
      URL2.canParse();
    });
    var WRONG_ARITY = fails(function() {
      return URL2.canParse.length !== 1;
    });
    $({ target: "URL", stat: true, forced: !THROWS_WITHOUT_ARGUMENTS || WRONG_ARITY }, {
      canParse: function canParse(url) {
        var length = validateArgumentsLength(arguments.length, 1);
        var urlString = toString(url);
        var base = length < 2 || arguments[1] === undefined ? undefined : toString(arguments[1]);
        try {
          return !!new URL2(urlString, base);
        } catch (error) {
          return false;
        }
      }
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/modules/web.url.parse.js
  var require_web_url_parse = __commonJS(function() {
    var $ = require_export();
    var getBuiltIn = require_get_built_in();
    var validateArgumentsLength = require_validate_arguments_length();
    var toString = require_to_string();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var URL2 = getBuiltIn("URL");
    $({ target: "URL", stat: true, forced: !USE_NATIVE_URL }, {
      parse: function parse(url) {
        var length = validateArgumentsLength(arguments.length, 1);
        var urlString = toString(url);
        var base = length < 2 || arguments[1] === undefined ? undefined : toString(arguments[1]);
        try {
          return new URL2(urlString, base);
        } catch (error) {
          return null;
        }
      }
    });
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/web/url.js
  var require_url = __commonJS(function(exports, module) {
    require_url_search_params();
    require_web_url();
    require_web_url_can_parse();
    require_web_url_parse();
    ;
    var path = require_path();
    module.exports = path.URL;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/stable/url/index.js
  var require_url2 = __commonJS(function(exports, module) {
    var parent = require_url();
    module.exports = parent;
  });

  // ../build/upstream/native-runtime/node_modules/core-js-pure/actual/url/index.js
  var require_url3 = __commonJS(function(exports, module) {
    var parent = require_url2();
    module.exports = parent;
  });

  // ../scripts/omp-core/platform.ts
  var import_url = __toESM(require_url3());

  // deps/quickbeam/priv/ts/event.ts
  var SYM_STOP_IMMEDIATE = Symbol("stopImmediate");

  // deps/quickbeam/priv/ts/abort.ts
  var SYM_ABORT = Symbol("abort");

  // deps/quickbeam/priv/ts/streams.ts
  function handleControllerStart(start, controller, onError) {
    try {
      const result = start?.(controller);
      if (result instanceof Promise) {
        result.catch((error) => onError(error));
      }
    } catch (error) {
      onError(error);
    }
  }
  var SYM_READ = Symbol("read");
  var SYM_RELEASE = Symbol("releaseLock");
  var SYM_CANCEL = Symbol("cancel");

  class ReadableStream {
    #queue = [];
    #state = "readable";
    #storedError = undefined;
    #source;
    #controller;
    #pulling = false;
    #waitingReaders = [];
    #locked = false;
    constructor(source) {
      this.#source = source;
      const controller = {
        desiredSize: 1,
        enqueue: (chunk) => {
          if (this.#state !== "readable")
            return;
          if (this.#waitingReaders.length > 0) {
            const reader = this.#waitingReaders.shift();
            if (reader)
              reader.resolve({ value: chunk, done: false });
            return;
          }
          this.#queue.push(chunk);
        },
        close: () => {
          if (this.#state !== "readable")
            return;
          this.#state = "closed";
          for (const reader of this.#waitingReaders) {
            reader.resolve({ value: undefined, done: true });
          }
          this.#waitingReaders = [];
        },
        error: (e) => {
          if (this.#state !== "readable")
            return;
          this.#state = "errored";
          this.#storedError = e;
          for (const reader of this.#waitingReaders) {
            reader.reject(e);
          }
          this.#waitingReaders = [];
          this.#queue = [];
        }
      };
      this.#controller = controller;
      handleControllerStart(source?.start, controller, (error) => controller.error(error));
    }
    get locked() {
      return this.#locked;
    }
    getReader() {
      if (this.#locked)
        throw new TypeError("ReadableStream is already locked");
      this.#locked = true;
      return new ReadableStreamDefaultReader(this);
    }
    async cancel(reason) {
      if (this.#locked)
        throw new TypeError("Cannot cancel a locked stream");
      await this.#source?.cancel?.(reason);
      this.#state = "closed";
      this.#queue = [];
    }
    pipeThrough(transform) {
      this.pipeTo(transform.writable);
      return transform.readable;
    }
    async pipeTo(dest) {
      const reader = this.getReader();
      const writer = dest.getWriter();
      try {
        for (;; ) {
          const { value, done } = await reader.read();
          if (done)
            break;
          await writer.write(value);
        }
        await writer.close();
      } catch (e) {
        await writer.abort(e);
      } finally {
        reader.releaseLock();
      }
    }
    tee() {
      const reader = this.getReader();
      let cancelled1 = false;
      let cancelled2 = false;
      let ctrl2;
      const stream1 = new ReadableStream({
        pull(controller) {
          return reader.read().then(({ value, done }) => {
            if (done) {
              if (!cancelled1)
                controller.close();
              if (!cancelled2)
                ctrl2.close();
              return;
            }
            if (!cancelled1)
              controller.enqueue(value);
            if (!cancelled2)
              ctrl2.enqueue(value);
          });
        },
        cancel() {
          cancelled1 = true;
        }
      });
      const stream2 = new ReadableStream({
        start(controller) {
          ctrl2 = controller;
        },
        cancel() {
          cancelled2 = true;
        }
      });
      return [stream1, stream2];
    }
    static from(iterable) {
      return new ReadableStream({
        async start(controller) {
          for await (const chunk of iterable) {
            controller.enqueue(chunk);
          }
          controller.close();
        }
      });
    }
    [SYM_READ]() {
      if (this.#state === "errored")
        return Promise.reject(this.#storedError);
      if (this.#queue.length > 0) {
        const value = this.#queue.shift();
        this.#callPull();
        return Promise.resolve({ value, done: false });
      }
      if (this.#state === "closed") {
        return Promise.resolve({ value: undefined, done: true });
      }
      this.#callPull();
      return new Promise((resolve, reject) => {
        this.#waitingReaders.push({ resolve, reject });
      });
    }
    [SYM_RELEASE]() {
      this.#locked = false;
    }
    [SYM_CANCEL](reason) {
      const result = this.#source?.cancel?.(reason);
      return result instanceof Promise ? result : Promise.resolve();
    }
    #callPull() {
      if (this.#pulling || this.#state !== "readable" || !this.#source?.pull)
        return;
      this.#pulling = true;
      try {
        const result = this.#source.pull(this.#controller);
        if (result instanceof Promise) {
          result.then(() => {
            this.#pulling = false;
          }).catch((e) => {
            this.#pulling = false;
            this.#controller.error(e);
          });
        } else {
          this.#pulling = false;
        }
      } catch (e) {
        this.#pulling = false;
        this.#controller.error(e);
      }
    }
    async* [Symbol.asyncIterator]() {
      const reader = this.getReader();
      try {
        for (;; ) {
          const { value, done } = await reader.read();
          if (done)
            break;
          yield value;
        }
      } finally {
        reader.releaseLock();
      }
    }
  }

  class ReadableStreamDefaultReader {
    #stream;
    #closed;
    #closedResolve;
    constructor(stream) {
      this.#stream = stream;
      this.#closed = new Promise((resolve) => {
        this.#closedResolve = resolve;
      });
    }
    get closed() {
      return this.#closed;
    }
    read() {
      return this.#stream[SYM_READ]();
    }
    releaseLock() {
      this.#stream[SYM_RELEASE]();
      this.#closedResolve();
    }
    async cancel(reason) {
      await this.#stream[SYM_CANCEL](reason);
      this.releaseLock();
    }
  }

  // deps/quickbeam/priv/ts/blob.ts
  var SYM_BYTES = Symbol("bytes");
  function isArrayBufferView(v) {
    return ArrayBuffer.isView(v);
  }
  function normalizePart(part) {
    if (part instanceof Blob)
      return part[SYM_BYTES]();
    if (part instanceof ArrayBuffer)
      return new Uint8Array(part);
    if (isArrayBufferView(part)) {
      return new Uint8Array(part.buffer, part.byteOffset, part.byteLength);
    }
    return new TextEncoder().encode(String(part));
  }
  function concatBytes(parts) {
    if (parts.length === 0)
      return new Uint8Array(0);
    if (parts.length === 1)
      return parts[0];
    let total = 0;
    for (const p of parts)
      total += p.length;
    const result = new Uint8Array(total);
    let offset = 0;
    for (const p of parts) {
      result.set(p, offset);
      offset += p.length;
    }
    return result;
  }
  function clampIndex(idx, size) {
    const i = Math.trunc(idx) || 0;
    if (i < 0)
      return Math.max(size + i, 0);
    return Math.min(i, size);
  }
  function normalizeType(raw) {
    return /^[\x20-\x7E]*$/.test(raw) ? raw.toLowerCase() : "";
  }

  class Blob {
    #parts;
    #type;
    constructor(parts, options) {
      this.#type = normalizeType(options?.type ?? "");
      this.#parts = (parts ?? []).map(normalizePart);
    }
    get size() {
      let total = 0;
      for (const p of this.#parts)
        total += p.length;
      return total;
    }
    get type() {
      return this.#type;
    }
    async arrayBuffer() {
      return this[SYM_BYTES]().buffer;
    }
    async text() {
      return new TextDecoder().decode(this[SYM_BYTES]());
    }
    async bytes() {
      return this[SYM_BYTES]().slice();
    }
    slice(start, end, contentType) {
      const bytes = this[SYM_BYTES]();
      const s = clampIndex(start ?? 0, bytes.length);
      const e = clampIndex(end ?? bytes.length, bytes.length);
      return new Blob([bytes.slice(s, Math.max(s, e))], {
        type: normalizeType(contentType ?? "")
      });
    }
    stream() {
      const bytes = this[SYM_BYTES]();
      return new ReadableStream({
        start(controller) {
          if (bytes.length > 0)
            controller.enqueue(bytes);
          controller.close();
        }
      });
    }
    [SYM_BYTES]() {
      return concatBytes(this.#parts);
    }
  }

  class File2 extends Blob {
    name;
    lastModified;
    constructor(parts, name, options) {
      super(parts, options);
      this.name = name;
      this.lastModified = options?.lastModified ?? Date.now();
    }
  }

  // deps/quickbeam/priv/ts/form-data.ts
  function normalizeValue(value, filename) {
    if (typeof value === "string")
      return value;
    if (value instanceof File2) {
      return filename !== undefined ? new File2([value[SYM_BYTES]().slice()], filename, { type: value.type, lastModified: value.lastModified }) : value;
    }
    return new File2([value[SYM_BYTES]().slice()], filename ?? "blob", { type: value.type });
  }

  class FormData2 {
    #entries = [];
    append(name, value, filename) {
      this.#entries.push({ name, value: normalizeValue(value, filename) });
    }
    set(name, value, filename) {
      const normalized = normalizeValue(value, filename);
      let found = false;
      let i = 0;
      while (i < this.#entries.length) {
        if (this.#entries[i].name === name) {
          if (!found) {
            this.#entries[i] = { name, value: normalized };
            found = true;
            i++;
          } else {
            this.#entries.splice(i, 1);
          }
        } else {
          i++;
        }
      }
      if (!found)
        this.#entries.push({ name, value: normalized });
    }
    get(name) {
      for (const entry of this.#entries) {
        if (entry.name === name)
          return entry.value;
      }
      return null;
    }
    getAll(name) {
      const result = [];
      for (const entry of this.#entries) {
        if (entry.name === name)
          result.push(entry.value);
      }
      return result;
    }
    has(name) {
      for (const entry of this.#entries) {
        if (entry.name === name)
          return true;
      }
      return false;
    }
    delete(name) {
      let i = 0;
      while (i < this.#entries.length) {
        if (this.#entries[i].name === name) {
          this.#entries.splice(i, 1);
        } else {
          i++;
        }
      }
    }
    forEach(callback, thisArg) {
      for (const entry of this.#entries) {
        callback.call(thisArg, entry.value, entry.name, this);
      }
    }
    *entries() {
      for (const entry of this.#entries) {
        yield [entry.name, entry.value];
      }
    }
    *keys() {
      for (const entry of this.#entries) {
        yield entry.name;
      }
    }
    *values() {
      for (const entry of this.#entries) {
        yield entry.value;
      }
    }
    [Symbol.iterator]() {
      return this.entries();
    }
  }

  // ../scripts/omp-core/platform.ts
  Object.assign(globalThis, { URL: import_url.default, File: File2, FormData: FormData2 });

  // ../build/upstream/oh-my-pi/packages/omptype/src/errors.ts
  function format(override, context, fallback) {
    return typeof override === "function" ? override(context) : override ?? fallback;
  }

  class OmpError {
    path;
    data;
    #rawExpected;
    #config;
    constructor(path, expected, data, config) {
      this.path = path;
      this.data = data;
      this.#rawExpected = expected;
      this.#config = config;
    }
    prefix(key) {
      this.path.unshift(key);
      return this;
    }
    configure(config) {
      this.#config = { ...this.#config, ...config };
      return this;
    }
    get code() {
      return errorCode(this.#rawExpected, this.data);
    }
    #context(expected, actual, problem = "") {
      const { description, rule } = describeExpectation(this.#rawExpected);
      return {
        code: this.code,
        path: this.path,
        propString: formatPath(this.path),
        data: this.data,
        expected,
        actual,
        problem,
        description,
        ...rule === undefined ? {} : { rule }
      };
    }
    get expected() {
      const actual = describeValue(this.data, this.#config?.preserveActual ? "predicate" : this.code);
      const parts = this.#rawExpected.split(" or ");
      const fallback = parts.length < 3 ? this.#rawExpected : `${parts.slice(0, -1).join(", ")} or ${parts[parts.length - 1]}`;
      return format(this.#config?.expected, this.#context(fallback, actual), fallback);
    }
    get actual() {
      const actual = describeValue(this.data, this.#config?.preserveActual ? "predicate" : this.code);
      const override = this.#config?.actual;
      return typeof override === "function" ? override(this.data) : override ?? actual;
    }
    get problem() {
      const expected = this.expected;
      const actual = this.actual;
      const fallback = this.data === MISSING ? `must be ${expected} (was missing)` : actual === "" ? `must be ${expected}` : `must be ${expected} (was ${actual})`;
      return format(this.#config?.problem, this.#context(expected, actual, fallback), fallback);
    }
    get message() {
      const expected = this.expected;
      const actual = this.actual;
      const problem = this.problem;
      const at = this.path.length === 0 ? "" : `${formatPath(this.path)} `;
      const messageActual = this.#config?.actual === undefined ? describeKind(this.data) : actual;
      return format(this.#config?.message, this.#context(expected, messageActual, problem), `${at}${problem}`);
    }
    toString() {
      return this.message;
    }
  }
  var MISSING = Symbol("omptype.missing");
  function stringifyValue(data) {
    const seen = new WeakSet;
    return JSON.stringify(data, (_key, value) => {
      if (typeof value !== "object" || value === null)
        return value;
      if (seen.has(value))
        return "(cycle)";
      seen.add(value);
      return value;
    }) ?? "an object";
  }
  function describeValue(data, code) {
    if (data === MISSING)
      return "missing";
    if (code === "undeclared")
      return "";
    if (code === "referenceSame")
      return "";
    if (code === "domain")
      return describeKind(data);
    if (data === null)
      return "null";
    if (Array.isArray(data))
      return "an array";
    switch (typeof data) {
      case "string":
        return data.length <= 40 ? JSON.stringify(data) : `a string (length ${data.length})`;
      case "number":
        return String(data);
      case "bigint":
        return `${data}n`;
      case "boolean":
        return String(data);
      case "undefined":
        return "undefined";
      case "object":
        return stringifyValue(data);
      case "function":
        return "a function";
      default:
        return "a symbol";
    }
  }
  function describeKind(data) {
    if (data === MISSING)
      return "missing";
    if (typeof data === "number" && Number.isNaN(data))
      return "NaN";
    if (data === null)
      return "null";
    if (Array.isArray(data))
      return "an object";
    switch (typeof data) {
      case "string":
        return "a string";
      case "number":
        return "a number";
      case "bigint":
        return "a bigint";
      case "boolean":
        return "boolean";
      case "undefined":
        return "undefined";
      case "object": {
        const ctor = Object.getPrototypeOf(data)?.constructor;
        return typeof ctor?.name === "string" && ctor.name !== "Object" ? ctor.name : "an object";
      }
      case "function":
        return "a function";
      default:
        return "a symbol";
    }
  }
  function describeExpectation(expected) {
    const divisor = /divisible by (\d+(?:\.\d+)?)/.exec(expected);
    if (divisor) {
      const rule = Number(divisor[1]);
      return { description: rule === 2 ? "even" : `divisible by ${rule}`, rule };
    }
    return { description: expected.replace(/^(?:an?|the) /, "") };
  }
  function formatPath(path) {
    let out = "";
    for (const key of path) {
      if (typeof key === "number")
        out += `[${key}]`;
      else if (typeof key === "symbol")
        out += `[${String(key)}]`;
      else
        out += out.length === 0 ? key : `.${key}`;
    }
    return out;
  }
  function errorCode(expected, data) {
    if (data === MISSING)
      return "required";
    if (expected === "removed")
      return "undeclared";
    if (expected.includes("serialized to the same value"))
      return "referenceSame";
    if (expected.includes("divisible by") || expected.includes("integer"))
      return "divisor";
    if (expected === "true" || expected === "false" || expected === "null" || expected === "undefined" || expected === "NaN" || expected === "Infinity" || expected === "-Infinity" || /^-?\d+(?:\.\d+)?n?$/.test(expected) || expected.includes(" or ") && expected.split(" or ").every((part) => /^".*"$|^-?\d+(?:\.\d+)?n?$|^(?:true|false|null|undefined)$/.test(part))) {
      return "unit";
    }
    if (expected.includes("at least") || expected.includes("more than") || expected.includes("timestamp after") || expected === "non-negative" || expected === "positive") {
      return "min";
    }
    if (expected.includes("at most") || expected.includes("less than") || expected.includes("timestamp before") || expected === "non-positive" || expected === "negative") {
      return "max";
    }
    if (expected.includes("matching") || expected.includes("format") || expected.includes("email") || expected.includes("parsable") || expected.includes("only digits")) {
      return "pattern";
    }
    if (expected.includes("predicate") || expected.includes("satisfying") || expected.includes("according to"))
      return "predicate";
    if (expected.startsWith('"') || expected.startsWith("the date "))
      return "unit";
    if (expected === "an Error" || expected === "a Date" || expected.startsWith("an instance of "))
      return "domain";
    if (expected.includes(" or ") && !expected.includes("IPv") || expected.endsWith(" instance") || expected.startsWith("a number representing") || [
      "a string",
      "a number",
      "a bigint",
      "a symbol",
      "boolean",
      "an object",
      "an array",
      "a tuple",
      "undefined",
      "null",
      "unknown",
      "never"
    ].includes(expected))
      return "domain";
    return "predicate";
  }

  class OmpErrors {
    #path;
    #expected;
    #data;
    #entry;
    #entries;
    #config;
    #separator = `
`;
    constructor(path, expected, data, config) {
      this.#path = path;
      this.#expected = expected;
      this.#data = data;
      this.#config = config;
    }
    get length() {
      return this.#entries?.length ?? 1;
    }
    get 0() {
      return this.#entries?.[0] ?? this.#getEntry();
    }
    static single(path, expected, data, config) {
      return new OmpErrors(path, expected, data, config);
    }
    #getEntry() {
      if (this.#entry)
        return this.#entry;
      const path = this.#path === undefined ? [] : Array.isArray(this.#path) ? [...this.#path] : [this.#path];
      const entry = new OmpError(path, this.#expected, this.#data, this.#config);
      this.#entry = entry;
      return entry;
    }
    append(other) {
      this.#entries ??= [this.#getEntry()];
      const entries = this.#entries;
      for (const entry of other)
        entries.push(entry);
      return this;
    }
    prefix(key) {
      if (this.#entries) {
        for (const entry of this.#entries)
          entry.prefix(key);
      } else {
        const path = this.#path;
        this.#path = path === undefined ? [key] : Array.isArray(path) ? [key, ...path] : [key, path];
        this.#entry = undefined;
      }
      return this;
    }
    configure(config) {
      if (this.#entries) {
        for (const entry of this.#entries)
          entry.configure(config);
      } else {
        this.#config = { ...this.#config, ...config };
        this.#entry = undefined;
      }
      return this;
    }
    get byPath() {
      const result = {};
      for (const entry of this)
        result[entry.path.map(String).join(".")] = entry;
      return result;
    }
    map(fn) {
      const result = [];
      let index = 0;
      for (const entry of this)
        result.push(fn(entry, index++, this));
      return result;
    }
    filter(fn) {
      const result = [];
      let index = 0;
      for (const entry of this) {
        if (fn(entry, index++, this))
          result.push(entry);
      }
      return result;
    }
    *[Symbol.iterator]() {
      if (this.#entries) {
        yield* this.#entries;
      } else {
        yield this.#getEntry();
      }
    }
    asAlternatives() {
      this.#separator = " or ";
      return this;
    }
    get summary() {
      const entries = [...this];
      if (this.#separator === `
` && entries.length > 1 && entries.every((entry) => Object.is(entry.data, entries[0].data) && entry.path.length === entries[0].path.length && entry.path.every((key, index) => key === entries[0].path[index]))) {
        const at = formatPath(entries[0].path);
        const actual = typeof entries[0].data === "string" ? JSON.stringify(entries[0].data) : String(entries[0].data);
        return `${at}${at === "" ? "" : " "}(${actual}) must be...
${entries.map((entry) => `  ◦ ${entry.expected}`).join(`
`)}`;
      }
      return entries.map((error) => error.message).join(this.#separator);
    }
    toString() {
      return this.summary;
    }
    throw() {
      throw new TraversalError(this);
    }
  }

  class TraversalError extends Error {
    errors;
    constructor(errors) {
      super(errors.summary);
      this.errors = errors;
      this.name = "TraversalError";
    }
  }

  class OmpTypeError extends Error {
    constructor(message) {
      super(message);
      this.name = "OmpTypeError";
    }
  }
  // ../build/upstream/oh-my-pi/packages/omptype/src/keywords.ts
  var NUMERIC = /^(?:(?!^-0\.?0*$)(?:-?(?:(?:0|[1-9]\d*)(?:\.\d+)?)|\.\d+?))$/;
  var INTEGER = /^[+-]?(?:0|[1-9]\d*)$/;
  var EMAIL = /^[\w%+.-]+@[\d.A-Za-z-]+\.[A-Za-z]{2,}$/;
  var SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][\dA-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][\dA-Za-z-]*))*))?(?:\+([\dA-Za-z-]+(?:\.[\dA-Za-z-]+)*))?$/;
  var UUID = /^[\da-f]{8}-[\da-f]{4}-[1-8][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i;
  var IPV4_SEGMENT = "(?:[0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])";
  var IPV4_ADDRESS = `(?:${IPV4_SEGMENT}[.]){3}${IPV4_SEGMENT}`;
  var IPV4 = new RegExp(`^${IPV4_ADDRESS}$`);
  var IPV6_SEGMENT = "(?:[0-9a-fA-F]{1,4})";
  var IPV6 = new RegExp("^(" + `(?:${IPV6_SEGMENT}:){7}(?:${IPV6_SEGMENT}|:)|` + `(?:${IPV6_SEGMENT}:){6}(?:${IPV4_ADDRESS}|:${IPV6_SEGMENT}|:)|` + `(?:${IPV6_SEGMENT}:){5}(?::${IPV4_ADDRESS}|(:${IPV6_SEGMENT}){1,2}|:)|` + `(?:${IPV6_SEGMENT}:){4}(?:(:${IPV6_SEGMENT}){0,1}:${IPV4_ADDRESS}|(:${IPV6_SEGMENT}){1,3}|:)|` + `(?:${IPV6_SEGMENT}:){3}(?:(:${IPV6_SEGMENT}){0,2}:${IPV4_ADDRESS}|(:${IPV6_SEGMENT}){1,4}|:)|` + `(?:${IPV6_SEGMENT}:){2}(?:(:${IPV6_SEGMENT}){0,3}:${IPV4_ADDRESS}|(:${IPV6_SEGMENT}){1,5}|:)|` + `(?:${IPV6_SEGMENT}:){1}(?:(:${IPV6_SEGMENT}){0,4}:${IPV4_ADDRESS}|(:${IPV6_SEGMENT}){1,6}|:)|` + `(?::((?::${IPV6_SEGMENT}){0,5}:${IPV4_ADDRESS}|(?::${IPV6_SEGMENT}){1,7}|:))` + ")(?:%[\\d.A-Za-z]{1,})?$");
  var ISO_DATE = /^([+-]?\d{4}(?!\d{2}\b))((-?)((0[1-9]|1[0-2])(\3([12]\d|0[1-9]|3[01]))?|W([0-4]\d|5[0-3])(-?[1-7])?|(00[1-9]|0[1-9]\d|[12]\d{2}|3([0-5]\d|6[1-6])))(T((([01]\d|2[0-3])((:?)[0-5]\d)?|24:?00)([,.]\d+(?!:))?)?(\17[0-5]\d([,.]\d+)?)?([Zz]|([+-])([01]\d|2[0-3]):?([0-5]\d)?)?)?)?$/;
  function pattern(regex, expected, format) {
    return {
      k: "refine",
      base: { k: "string" },
      pred: (value) => {
        regex.lastIndex = 0;
        return regex.test(value);
      },
      expected,
      json: format === undefined ? { pattern: regex.source } : { pattern: regex.source, format }
    };
  }
  function morph(input, fn, out) {
    return { k: "morph", input, fn: (value, context) => fn(value, context), out };
  }
  function parsableJson() {
    return {
      k: "refine",
      base: { k: "string" },
      pred: (value) => {
        try {
          JSON.parse(value);
          return true;
        } catch {
          return false;
        }
      },
      expected: "a JSON string",
      json: { contentMediaType: "application/json" }
    };
  }
  function parsableDate(expected = "a parsable date") {
    return {
      k: "refine",
      base: { k: "string" },
      pred: (value) => !Number.isNaN(new Date(value).valueOf()),
      expected,
      json: { format: "date-time" }
    };
  }
  function normalize(form) {
    return morph({ k: "string" }, (value) => value.normalize(form), patternForNormalized(form));
  }
  function patternForNormalized(form) {
    return {
      k: "refine",
      base: { k: "string" },
      pred: (value) => value.normalize(form) === value,
      expected: `${form}-normalized unicode`
    };
  }
  function uuidVersion(version) {
    return pattern(new RegExp(`^[\\da-f]{8}-[\\da-f]{4}-${version}[\\da-f]{3}-[89ab][\\da-f]{3}-[\\da-f]{12}$`, "i"), `a UUIDv${version}`, "uuid");
  }
  function isLuhnValid(input) {
    const value = input.replace(/[ -]+/g, "");
    let sum = 0;
    let double = false;
    for (let index = value.length - 1;index >= 0; index--) {
      let digit = Number(value[index]);
      if (double) {
        digit *= 2;
        if (digit > 9)
          digit -= 9;
      }
      sum += digit;
      double = !double;
    }
    return value.length > 0 && sum % 10 === 0;
  }
  function finiteNumber(expected = "a number") {
    return {
      k: "refine",
      base: { k: "unknown" },
      pred: (value) => typeof value === "number" && !Number.isNaN(value),
      expected
    };
  }
  function jsonObject() {
    const value = {};
    const resolveValue = () => value.current;
    const object = {
      k: "object",
      props: [],
      index: { k: "alias", name: "$jsonValue", resolve: resolveValue },
      extras: "keep"
    };
    const array = {
      k: "array",
      el: { k: "alias", name: "$jsonValue", resolve: resolveValue },
      desc: "an object"
    };
    value.current = {
      k: "union",
      members: [
        object,
        array,
        { k: "number" },
        { k: "string" },
        { k: "lit", v: false },
        { k: "null" },
        { k: "lit", v: true }
      ]
    };
    return object;
  }
  function instance(ctor, name) {
    return { k: "instance", ctor, expected: `${/^[AEIOU]/.test(name) ? "an" : "a"} ${name} instance` };
  }
  var keywordFactories = {
    string: () => ({ k: "string" }),
    Key: () => ({ k: "union", members: [{ k: "string" }, { k: "symbol" }] }),
    "unknown.any": () => ({ k: "unknown" }),
    Array: () => ({ k: "array", el: { k: "unknown" } }),
    Function: () => instance(Function, "Function"),
    RegExp: () => instance(RegExp, "RegExp"),
    File: () => instance(File, "File"),
    Error: () => instance(Error, "Error"),
    Set: () => instance(Set, "Set"),
    Map: () => instance(Map, "Map"),
    WeakSet: () => instance(WeakSet, "WeakSet"),
    WeakMap: () => instance(WeakMap, "WeakMap"),
    Promise: () => instance(Promise, "Promise"),
    FormData: () => instance(FormData, "FormData"),
    "FormData.parse": () => ({
      k: "morph",
      input: instance(FormData, "FormData"),
      fn: (value) => {
        const out = {};
        for (const [key, entry] of value.entries()) {
          const current = out[key];
          out[key] = current === undefined ? entry : Array.isArray(current) ? [...current, entry] : [current, entry];
        }
        return out;
      },
      out: { k: "object", props: [], index: { k: "unknown" }, extras: "keep" }
    }),
    "object.json": jsonObject,
    "object.json.stringify": () => ({
      k: "morph",
      input: jsonObject(),
      fn: (value) => JSON.stringify(value),
      out: { k: "string" }
    }),
    "number.epoch": () => ({
      k: "refine",
      base: {
        k: "refine",
        base: {
          k: "refine",
          base: finiteNumber("a number representing a Unix timestamp"),
          pred: (value) => Number.isInteger(value),
          expected: "an integer representing a Unix timestamp"
        },
        pred: (value) => value >= -8640000000000000,
        expected: "a Unix timestamp after -8640000000000000"
      },
      pred: (value) => value <= 8640000000000000,
      expected: "a Unix timestamp before 8640000000000000"
    }),
    "number.safe": () => ({
      k: "refine",
      base: {
        k: "refine",
        base: finiteNumber(),
        pred: (value) => value >= Number.MIN_SAFE_INTEGER,
        expected: `at least ${Number.MIN_SAFE_INTEGER}`
      },
      pred: (value) => value <= Number.MAX_SAFE_INTEGER,
      expected: `at most ${Number.MAX_SAFE_INTEGER}`
    }),
    "number.NaN": () => ({
      k: "refine",
      base: { k: "unknown" },
      pred: Number.isNaN,
      expected: "NaN"
    }),
    "number.Infinity": () => ({ k: "lit", v: Number.POSITIVE_INFINITY }),
    "number.NegativeInfinity": () => ({ k: "lit", v: Number.NEGATIVE_INFINITY }),
    "string.alpha": () => pattern(/^[A-Za-z]*$/, "only letters"),
    "string.alphanumeric": () => pattern(/^[\dA-Za-z]*$/, "only letters and digits 0-9"),
    "string.hex": () => pattern(/^[\dA-Fa-f]+$/, "hex characters only"),
    "string.base64": () => pattern(/^(?:[\d+/A-Za-z]{4})*(?:[\d+/A-Za-z]{2}==|[\d+/A-Za-z]{3}=)?$/, "base64-encoded"),
    "string.base64.url": () => pattern(/^(?:[\w-]{4})*(?:[\w-]{2}(?:==|%3D%3D)?|[\w-]{3}(?:=|%3D)?)?$/, "base64url-encoded"),
    "string.capitalize": () => morph({ k: "string" }, (value) => value.charAt(0).toUpperCase() + value.slice(1)),
    "string.capitalize.preformatted": () => pattern(/^[A-Z].*$/, "capitalized"),
    "string.creditCard": () => ({
      k: "refine",
      base: pattern(/^(?:4\d{12}(?:\d{3,6})?|5[1-5]\d{14}|3[47]\d{13}|6(?:011|5\d\d)\d{12,15})$/, "a credit card number"),
      pred: (value) => isLuhnValid(value),
      expected: "a credit card number"
    }),
    "string.date": () => parsableDate(),
    "string.date.parse": () => morph(parsableDate(), (value) => new Date(value), { k: "instance", ctor: Date, expected: "a Date" }),
    "string.date.iso": () => pattern(ISO_DATE, "an ISO 8601 date", "date-time"),
    "string.date.iso.parse": () => morph(pattern(ISO_DATE, "an ISO 8601 date", "date-time"), (value) => new Date(value), {
      k: "instance",
      ctor: Date,
      expected: "a Date"
    }),
    "string.date.epoch": () => pattern(INTEGER, "an integer string representing a Unix timestamp"),
    "string.date.epoch.parse": () => morph(pattern(INTEGER, "an integer string representing a Unix timestamp"), (value) => new Date(Number(value)), {
      k: "instance",
      ctor: Date,
      expected: "a Date"
    }),
    "string.digits": () => pattern(/^\d*$/, "only digits 0-9"),
    "string.email": () => pattern(EMAIL, "an email address", "email"),
    "string.integer": () => pattern(INTEGER, "a well-formed integer string"),
    "string.integer.parse": () => morph(pattern(INTEGER, "a well-formed integer string"), (value, context) => {
      const parsed = Number.parseInt(value, 10);
      return Number.isSafeInteger(parsed) ? parsed : context.error("a safe integer string");
    }, { k: "number", int: true }),
    "string.ip": () => ({
      k: "union",
      members: [pattern(IPV4, "an IPv4 address", "ipv4"), pattern(IPV6, "an IPv6 address", "ipv6")]
    }),
    "string.ip.v4": () => pattern(IPV4, "an IPv4 address", "ipv4"),
    "string.ip.v6": () => pattern(IPV6, "an IPv6 address", "ipv6"),
    "string.json": () => parsableJson(),
    "string.json.parse": () => morph(parsableJson(), (value, context) => {
      try {
        return JSON.parse(value);
      } catch {
        return context.error("a JSON string");
      }
    }),
    "string.lower": () => morph({ k: "string" }, (value) => value.toLowerCase()),
    "string.lower.preformatted": () => pattern(/^[a-z]*$/, "only lowercase letters"),
    "string.normalize": () => normalize("NFC"),
    "string.normalize.NFC": () => normalize("NFC"),
    "string.normalize.NFC.preformatted": () => patternForNormalized("NFC"),
    "string.normalize.NFD": () => normalize("NFD"),
    "string.normalize.NFD.preformatted": () => patternForNormalized("NFD"),
    "string.normalize.NFKC": () => normalize("NFKC"),
    "string.normalize.NFKC.preformatted": () => patternForNormalized("NFKC"),
    "string.normalize.NFKD": () => normalize("NFKD"),
    "string.normalize.NFKD.preformatted": () => patternForNormalized("NFKD"),
    "string.numeric": () => pattern(NUMERIC, "a well-formed numeric string"),
    "string.numeric.parse": () => morph(pattern(NUMERIC, "a well-formed numeric string"), (value) => Number.parseFloat(value), { k: "number" }),
    "string.regex": () => ({
      k: "refine",
      base: { k: "string" },
      pred: (value) => {
        try {
          new RegExp(value);
          return true;
        } catch {
          return false;
        }
      },
      expected: "a regex pattern",
      json: { format: "regex" }
    }),
    "string.semver": () => pattern(SEMVER, "a semantic version"),
    "string.trim": () => morph({ k: "string" }, (value) => value.trim()),
    "string.trim.preformatted": () => pattern(/^\S.*\S$|^\S?$/, "trimmed"),
    "string.upper": () => morph({ k: "string" }, (value) => value.toUpperCase()),
    "string.upper.preformatted": () => pattern(/^[A-Z]*$/, "only uppercase letters"),
    "string.url": () => ({ k: "string", url: true }),
    "string.url.parse": () => morph({ k: "string", url: true }, (value) => new URL(value), { k: "instance", ctor: URL, expected: "a URL" }),
    "string.uuid": () => pattern(UUID, "a UUID", "uuid"),
    "string.uuid.v1": () => uuidVersion("1"),
    "string.uuid.v2": () => uuidVersion("2"),
    "string.uuid.v3": () => uuidVersion("3"),
    "string.uuid.v4": () => uuidVersion("4"),
    "string.uuid.v5": () => uuidVersion("5"),
    "string.uuid.v6": () => uuidVersion("6"),
    "string.uuid.v7": () => uuidVersion("7"),
    "string.uuid.v8": () => uuidVersion("8"),
    "parse.number": () => morph(pattern(NUMERIC, "a well-formed numeric string"), (value) => Number.parseFloat(value), { k: "number" }),
    "parse.integer": () => morph(pattern(INTEGER, "a well-formed integer string"), (value) => Number.parseInt(value, 10), {
      k: "number",
      int: true
    }),
    "parse.json": () => keywordFactories["string.json.parse"](),
    "parse.date": () => keywordFactories["string.date.parse"](),
    "parse.url": () => keywordFactories["string.url.parse"](),
    "parse.boolean": () => morph(pattern(/^(?:true|false)$/, "a boolean string"), (value) => value === "true", { k: "boolean" }),
    "parse.bigint": () => morph(pattern(INTEGER, "an integer string"), (value) => BigInt(value), { k: "bigint" })
  };
  function keywordIR(name) {
    return keywordFactories[name]?.();
  }
  function patternIR(regex) {
    return pattern(regex, `a string matching ${regex}`);
  }
  function templateIR(source) {
    let patternSource = "^";
    let index = 0;
    const placeholder = /\$\{(string|number|bigint|boolean)\}/g;
    for (let match = placeholder.exec(source);match; match = placeholder.exec(source)) {
      patternSource += escapeRegex(source.slice(index, match.index));
      switch (match[1]) {
        case "number":
          patternSource += "[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)";
          break;
        case "bigint":
          patternSource += "[+-]?\\d+";
          break;
        case "boolean":
          patternSource += "(?:true|false)";
          break;
        default:
          patternSource += ".*";
      }
      index = match.index + match[0].length;
    }
    patternSource += `${escapeRegex(source.slice(index))}$`;
    return pattern(new RegExp(patternSource), `a string matching \`${source}\``);
  }
  function escapeRegex(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  // ../build/upstream/oh-my-pi/packages/omptype/src/ir.ts
  var IR_BRAND = Symbol("omptype.schema");
  var kMorph = Symbol("omptype.hasMorph");
  var kMorphOwner = Symbol("omptype.hasMorphOwner");
  var kAlias = Symbol("omptype.hasAlias");
  var kAliasOwner = Symbol("omptype.hasAliasOwner");
  var kSimple = Symbol("omptype.simple");
  var kSimpleOwner = Symbol("omptype.simpleOwner");
  var SIMPLE_OPS = "|&()[]=?%,#";
  function tokenize(src) {
    const toks = [];
    let i = 0;
    const n = src.length;
    while (i < n) {
      const c = src[i];
      if (c === " " || c === "\t" || c === `
` || c === "\r") {
        i++;
        continue;
      }
      if (c === "d" && (src[i + 1] === "'" || src[i + 1] === '"')) {
        const quote = src[i + 1];
        const end = src.indexOf(quote, i + 2);
        if (end < 0)
          throw new OmpTypeError(`unterminated date literal in "${src}"`);
        const source = src.slice(i + 2, end).trim();
        const value = /^\d+$/.test(source) ? new Date(Number(source)) : new Date(source);
        if (Number.isNaN(value.valueOf()))
          throw new OmpTypeError(`invalid date literal in "${src}"`);
        toks.push({ t: "date", v: value });
        i = end + 1;
        continue;
      }
      if (c === "'" || c === '"') {
        let j = i + 1;
        let value = "";
        for (;j < n && src[j] !== c; j++) {
          if (src[j] === "\\") {
            j++;
            if (j >= n)
              break;
          }
          value += src[j];
        }
        if (j >= n)
          throw new OmpTypeError(`unterminated string literal in "${src}"`);
        toks.push({ t: "str", v: value });
        i = j + 1;
        continue;
      }
      if (c === "/") {
        let j = i + 1;
        for (;j < n; j++) {
          if (src[j] === "\\")
            j++;
          else if (src[j] === "/")
            break;
        }
        if (j >= n)
          throw new OmpTypeError(`unterminated regular expression in "${src}"`);
        let end = j + 1;
        while (end < n && /[dgimsuvy]/.test(src[end]))
          end++;
        const source = src.slice(i + 1, j);
        const flags = src.slice(j + 1, end);
        try {
          toks.push({ t: "regex", v: new RegExp(source, flags) });
        } catch {
          throw new OmpTypeError(`invalid regular expression "${src.slice(i, end)}"`);
        }
        i = end;
        continue;
      }
      if (c >= "0" && c <= "9" || c === "-" && i + 1 < n && src[i + 1] >= "0" && src[i + 1] <= "9") {
        let j = i + 1;
        while (j < n && /[\w.+-]/.test(src[j]))
          j++;
        const raw = src.slice(i, j);
        if (/^-?(?:0|[1-9]\d*)n$/.test(raw) && raw !== "-0n") {
          toks.push({ t: "bigint", v: BigInt(raw.slice(0, -1)) });
        } else {
          const valid = /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/.test(raw) && !Object.is(Number(raw), -0) && String(Number(raw)) === raw;
          if (!valid)
            throw new OmpTypeError(`Malformed number literal '${raw}'`);
          toks.push({ t: "num", v: Number(raw) });
        }
        i = j;
        continue;
      }
      if (/[a-zA-Z_$]/.test(c)) {
        let j = i + 1;
        while (j < n && /[\w.$]/.test(src[j]))
          j++;
        toks.push({ t: "id", v: src.slice(i, j) });
        i = j;
        continue;
      }
      if (c === "<" || c === ">") {
        if (src[i + 1] === "=") {
          toks.push({ t: "op", v: `${c}=` });
          i += 2;
        } else {
          toks.push({ t: "op", v: c });
          i++;
        }
        continue;
      }
      if (c === "=" && src[i + 1] === "=") {
        toks.push({ t: "op", v: "==" });
        i += 2;
        continue;
      }
      if (SIMPLE_OPS.includes(c)) {
        toks.push({ t: "op", v: c });
        i++;
        continue;
      }
      throw new OmpTypeError(`unexpected character '${c}' in "${src}"`);
    }
    return toks;
  }
  var CMP = { "<": true, "<=": true, ">": true, ">=": true };
  var KEYWORDS = {
    number: () => ({ k: "number" }),
    "number.integer": () => ({ k: "number", int: true }),
    boolean: () => ({ k: "boolean" }),
    bigint: () => ({ k: "bigint" }),
    symbol: () => ({ k: "symbol" }),
    never: () => ({ k: "never" }),
    null: () => ({ k: "null" }),
    undefined: () => ({ k: "undefined" }),
    unknown: () => ({ k: "unknown" }),
    any: () => ({ k: "unknown" }),
    object: () => ({ k: "anyobject" }),
    Date: () => ({ k: "instance", ctor: Date, expected: "a Date" }),
    true: () => ({ k: "lit", v: true }),
    false: () => ({ k: "lit", v: false })
  };
  var THIS_ONLY_RESOLVERS = new WeakSet;
  function markThisOnlyResolver(resolve) {
    THIS_ONLY_RESOLVERS.add(resolve);
  }

  class StrParser {
    #toks;
    #pos = 0;
    #src;
    #resolve;
    constructor(src, resolve) {
      this.#src = src;
      this.#resolve = resolve;
      this.#toks = tokenize(src);
    }
    #peek(offset = 0) {
      return this.#toks[this.#pos + offset];
    }
    #next() {
      const t = this.#toks[this.#pos++];
      if (!t)
        throw new OmpTypeError(`unexpected end of definition "${this.#src}"`);
      return t;
    }
    #eatOp(v) {
      const t = this.#peek();
      if (t?.t === "op" && t.v === v) {
        this.#pos++;
        return true;
      }
      return false;
    }
    parseTop() {
      const ir = this.parseUnion();
      let def;
      let hasDefault = false;
      if (this.#eatOp("=")) {
        const t = this.#next();
        if (t.t === "num" || t.t === "bigint" || t.t === "date" || t.t === "str")
          def = t.v;
        else if (t.t === "id" && (t.v === "true" || t.v === "false"))
          def = t.v === "true";
        else if (t.t === "id" && t.v === "null")
          def = null;
        else if (t.t === "id" && t.v === "undefined")
          def = undefined;
        else
          throw new OmpTypeError(`unsupported default literal in "${this.#src}"`);
        hasDefault = true;
      }
      const optional = this.#eatOp("?");
      this.#expectEnd();
      return { ir, def, hasDefault, optional };
    }
    #expectEnd() {
      if (this.#pos < this.#toks.length) {
        throw new OmpTypeError(`trailing tokens in definition "${this.#src}"`);
      }
    }
    parseUnion() {
      const first = this.parseIntersection();
      if (!this.#eatOp("|"))
        return first;
      const members = [first, this.parseIntersection()];
      while (this.#eatOp("|"))
        members.push(this.parseIntersection());
      return { k: "union", members };
    }
    parseIntersection() {
      const first = this.parseBounded();
      if (!this.#eatOp("&"))
        return first;
      const members = [first, this.parseBounded()];
      while (this.#eatOp("&"))
        members.push(this.parseBounded());
      const literal = members.find((member) => member.k === "lit");
      if (literal && typeof literal.v === "number") {
        for (const member of members) {
          if (member.k === "number" && (member.int && !Number.isInteger(literal.v) || member.divisor !== undefined && literal.v % member.divisor !== 0 || member.min !== undefined && (member.xmin ? literal.v <= member.min : literal.v < member.min) || member.max !== undefined && (member.xmax ? literal.v >= member.max : literal.v > member.max))) {
            throw new OmpTypeError("literal is excluded by intersection");
          }
        }
        return literal;
      }
      return { k: "intersection", members };
    }
    parseBounded() {
      const t = this.#peek();
      const t1 = this.#peek(1);
      if ((t?.t === "num" || t?.t === "date") && t1?.t === "op" && (t1.v === "<" || t1.v === "<=")) {
        const lo = t.v;
        this.#pos += 2;
        let node = this.#eatDivisor(this.parsePostfix());
        node = applyBound(node, flip(t1.v), lo, this.#src);
        const t2 = this.#peek();
        if (!(t2?.t === "op" && CMP[t2.v])) {
          throw new OmpTypeError(`left bound requires a corresponding right bound in "${this.#src}"`);
        }
        if (t2.v === ">" || t2.v === ">=") {
          throw new OmpTypeError(`right bound must use < or <= in "${this.#src}"`);
        }
        this.#pos++;
        const hi = this.#next();
        if (hi.t !== "num" && hi.t !== "date") {
          throw new OmpTypeError(`expected bound after comparator in "${this.#src}"`);
        }
        node = applyBound(node, t2.v, hi.v, this.#src);
        return this.#eatArraySuffixes(node);
      }
      let node = this.#eatDivisor(this.parsePostfix());
      const t2 = this.#peek();
      if (t2?.t === "op" && t2.v === "==") {
        this.#pos++;
        const limit = this.#next();
        if (limit.t !== "num" && limit.t !== "bigint" && limit.t !== "date") {
          throw new OmpTypeError(`expected literal after == in "${this.#src}"`);
        }
        node = applyEquality(node, limit.v, this.#src);
      } else if (t2?.t === "op" && CMP[t2.v] && (this.#peek(1)?.t === "num" || this.#peek(1)?.t === "date")) {
        this.#pos++;
        const limit = this.#next();
        node = applyBound(node, t2.v, limit.v, this.#src);
        node = this.#eatArraySuffixes(node);
      }
      return node;
    }
    #eatDivisor(node) {
      if (!this.#eatOp("%"))
        return node;
      const divisor = this.#next();
      if (divisor.t !== "num")
        throw new OmpTypeError(`expected number after % in "${this.#src}"`);
      if (node.k !== "number")
        throw new OmpTypeError(`% requires number in "${this.#src}"`);
      if (!Number.isFinite(divisor.v) || !Number.isInteger(divisor.v) || divisor.v === 0)
        throw new OmpTypeError(`divisor must be a non-zero integer in "${this.#src}"`);
      return { ...node, divisor: Math.abs(divisor.v) };
    }
    #eatArraySuffixes(node) {
      for (;; ) {
        const t = this.#peek();
        if (!(t?.t === "op" && t.v === "["))
          return node;
        this.#pos++;
        if (!this.#eatOp("]"))
          throw new OmpTypeError(`expected ']' in "${this.#src}"`);
        node = { k: "array", el: node };
      }
    }
    parsePostfix() {
      let node = this.parsePrimary();
      for (;; ) {
        const t = this.#peek();
        if (t?.t === "op" && t.v === "[") {
          this.#pos++;
          if (!this.#eatOp("]"))
            throw new OmpTypeError(`expected ']' in "${this.#src}"`);
          node = { k: "array", el: node };
          continue;
        }
        if (t?.t === "op" && t.v === "#") {
          this.#pos++;
          const name = this.#next();
          if (name.t !== "id")
            throw new OmpTypeError(`expected brand name after # in "${this.#src}"`);
          continue;
        }
        break;
      }
      return node;
    }
    #parseGenericArguments() {
      this.#eatOp("<");
      const arguments_ = [];
      if (this.#eatOp(">"))
        return arguments_;
      for (;; ) {
        arguments_.push(this.parseUnion());
        if (this.#eatOp(">"))
          return arguments_;
        if (!this.#eatOp(","))
          throw new OmpTypeError(`expected ',' or '>' in "${this.#src}"`);
        const next = this.#peek();
        if (next?.t === "op" && (next.v === "," || next.v === ">")) {
          throw new OmpTypeError(`generic arguments cannot be empty in "${this.#src}"`);
        }
      }
    }
    parsePrimary() {
      const t = this.#next();
      if (t.t === "op" && t.v === "(") {
        const inner = this.parseUnion();
        if (!this.#eatOp(")"))
          throw new OmpTypeError(`expected ')' in "${this.#src}"`);
        return inner;
      }
      if (t.t === "str" || t.t === "num" || t.t === "bigint" || t.t === "date")
        return { k: "lit", v: t.v };
      if (t.t === "regex")
        return patternIR(t.v);
      if (t.t === "id") {
        if (t.v === "keyof") {
          try {
            return keyOf(this.parsePostfix());
          } catch (error) {
            if (error instanceof OmpTypeError)
              throw new OmpTypeError("keyof operand must be an object");
            throw error;
          }
        }
        if (t.v === "Array.liftFrom" && this.#peek()?.t === "op" && this.#peek()?.v === "<") {
          this.#pos++;
          const element = this.parsePrimary();
          if (!this.#eatOp(">"))
            throw new OmpTypeError(`expected '>' in "${this.#src}"`);
          const array = { k: "array", el: element, desc: "an object" };
          return {
            k: "morph",
            input: { k: "union", members: [element, array] },
            fn: (value) => Array.isArray(value) ? value : [value],
            out: array
          };
        }
        if (t.v === "Record" && this.#peek()?.t === "op" && this.#peek()?.v === "<") {
          const arguments_ = this.#parseGenericArguments();
          if (arguments_.length !== 2)
            throw new OmpTypeError("Record requires two arguments");
          return { k: "object", props: [], index: arguments_[1], extras: "keep" };
        }
        if (this.#peek()?.t === "op" && this.#peek()?.v === "<" && this.#resolve?.hasGeneric?.(t.v)) {
          const arguments_ = this.#parseGenericArguments();
          const instantiated = this.#resolve.generic?.(t.v, arguments_);
          if (!instantiated)
            throw new OmpTypeError(`unknown generic "${t.v}" in "${this.#src}"`);
          return instantiated;
        }
        const scoped = this.#resolve?.(t.v);
        const make = KEYWORDS[t.v];
        const keyword = scoped ?? make?.() ?? keywordIR(t.v);
        if (!keyword)
          throw new OmpTypeError(`unknown keyword "${t.v}" in "${this.#src}"`);
        return keyword;
      }
      throw new OmpTypeError(`unexpected token in "${this.#src}"`);
    }
  }
  var STRING_DEF_CACHE_MAX = 1024;
  var stringDefCache = new Map;
  function isWhitespaceAt(src, index) {
    const code = src.charCodeAt(index);
    return code === 32 || code >= 9 && code <= 13 || code > 127 && /\s/.test(src[index]);
  }
  function parseLiteralUnion(src) {
    const members = [];
    let index = 0;
    while (index < src.length && isWhitespaceAt(src, index))
      index++;
    for (;; ) {
      const quote = src[index];
      if (quote !== "'" && quote !== '"')
        return;
      const end = src.indexOf(quote, index + 1);
      if (end < 0)
        return;
      members.push({ k: "lit", v: src.slice(index + 1, end) });
      index = end + 1;
      while (index < src.length && isWhitespaceAt(src, index))
        index++;
      if (index === src.length) {
        const ir = members.length === 1 ? members[0] : { k: "union", members };
        let simple = true;
        for (let member = 1;simple && member < members.length; member++) {
          for (let previous = 0;previous < member; previous++) {
            if (members[previous].k === "lit" && members[previous].v === members[member].v) {
              simple = false;
              break;
            }
          }
        }
        ir[kSimple] = simple;
        ir[kSimpleOwner] = ir;
        return ir;
      }
      if (src[index] !== "|")
        return;
      index++;
      while (index < src.length && isWhitespaceAt(src, index))
        index++;
    }
  }
  function genericArguments(src) {
    const open = src.indexOf("<");
    if (open < 1 || !src.endsWith(">"))
      return;
    const name = src.slice(0, open).trim();
    const body = src.slice(open + 1, -1);
    const args = [];
    let depth = 0;
    let quote = "";
    let start = 0;
    for (let index = 0;index < body.length; index++) {
      const char = body[index];
      if (quote !== "") {
        if (char === quote && body[index - 1] !== "\\")
          quote = "";
        continue;
      }
      if (char === "'" || char === '"' || char === "`") {
        quote = char;
      } else if (char === "<" || char === "(" || char === "[") {
        depth++;
      } else if (char === ">" || char === ")" || char === "]") {
        depth--;
      } else if (char === "," && depth === 0) {
        args.push(body.slice(start, index).trim());
        start = index + 1;
      }
    }
    args.push(body.slice(start).trim());
    return { name, args };
  }
  function genericKeys(ir) {
    const keys = new Set;
    const visit = (node) => {
      if (node.k === "lit" && typeof node.v === "string")
        keys.add(node.v);
      else if (node.k === "union")
        for (const member of node.members)
          visit(member);
    };
    visit(ir);
    return keys;
  }
  function resolveStructuralIR(ir) {
    const seen = new Set;
    while (ir.k === "alias") {
      if (seen.has(ir))
        throw new OmpTypeError(`cannot structurally transform recursive alias "${ir.name}"`);
      seen.add(ir);
      ir = ir.resolve();
    }
    return ir;
  }
  function mergeObjectIR(left, right) {
    left = resolveStructuralIR(left);
    right = resolveStructuralIR(right);
    if (left.k !== "object" || right.k !== "object") {
      throw new OmpTypeError("Merge requires object arguments");
    }
    const props = [...left.props];
    for (const prop of right.props) {
      const index = props.findIndex((candidate) => candidate.key === prop.key);
      if (index < 0)
        props.push(prop);
      else
        props[index] = prop;
    }
    return {
      k: "object",
      props,
      index: right.index ?? left.index,
      symbolIndex: right.symbolIndex ?? left.symbolIndex,
      patternIndexes: left.patternIndexes === undefined && right.patternIndexes === undefined ? undefined : [...left.patternIndexes ?? [], ...right.patternIndexes ?? []],
      extras: right.extras === "keep" ? left.extras : right.extras
    };
  }
  function parseGeneric(src, resolve) {
    const generic = genericArguments(src);
    if (generic === undefined)
      return;
    if (generic.name === "Array.liftFrom" && generic.args.length === 1) {
      const element = parseDef(generic.args[0], resolve);
      const array = { k: "array", el: element, desc: "an object" };
      return {
        k: "morph",
        input: { k: "union", members: [element, array] },
        fn: (value) => Array.isArray(value) ? value : [value],
        out: array
      };
    }
    if (generic.name === "Record" && generic.args.length === 2) {
      return { k: "object", props: [], index: parseDef(generic.args[1], resolve), extras: "keep" };
    }
    if ((generic.name === "Extract" || generic.name === "Exclude") && generic.args.length === 2) {
      return distributeFilter(parseDef(generic.args[0], resolve), parseDef(generic.args[1], resolve), generic.name === "Extract");
    }
    if ((generic.name === "Partial" || generic.name === "Required") && generic.args.length === 1) {
      const object = resolveStructuralIR(parseDef(generic.args[0], resolve));
      if (object.k !== "object")
        throw new OmpTypeError(`${generic.name} requires an object`);
      const optional = generic.name === "Partial";
      return { ...object, props: object.props.map((prop) => ({ ...prop, opt: optional })) };
    }
    if ((generic.name === "Pick" || generic.name === "Omit") && generic.args.length === 2) {
      const object = resolveStructuralIR(parseDef(generic.args[0], resolve));
      if (object.k !== "object")
        throw new OmpTypeError(`${generic.name} requires an object`);
      const keys = genericKeys(parseDef(generic.args[1], resolve));
      const pick = generic.name === "Pick";
      return { ...object, props: object.props.filter((prop) => keys.has(prop.key) === pick) };
    }
    if (generic.name === "Merge" && generic.args.length === 2) {
      return mergeObjectIR(parseDef(generic.args[0], resolve), parseDef(generic.args[1], resolve));
    }
    return;
  }
  var isAssignable = () => false;
  function useAssignability(compare) {
    isAssignable = compare;
  }
  function distributeFilter(base, target, keepAssignable) {
    const resolved = base.k === "alias" ? base.resolve() : base;
    const members = resolved.k === "union" ? resolved.members : [resolved];
    const retained = members.filter((member) => isAssignable(member, target) === keepAssignable);
    if (retained.length === 0)
      return { k: "never" };
    return retained.length === 1 ? retained[0] : { k: "union", members: retained };
  }
  function parseRegexExec(src) {
    if (!src.startsWith("x/"))
      return;
    const end = src.lastIndexOf("/");
    if (end < 2)
      throw new OmpTypeError(`unterminated regular expression in "${src}"`);
    let regex;
    try {
      regex = new RegExp(src.slice(2, end), src.slice(end + 1));
    } catch {
      throw new OmpTypeError(`invalid regular expression "${src.slice(1)}"`);
    }
    return {
      k: "morph",
      input: patternIR(regex),
      fn: (value, context) => {
        regex.lastIndex = 0;
        return regex.exec(value) ?? context.error(`a string matching ${regex}`);
      }
    };
  }
  function parseStringDef(src, resolve) {
    const cacheable = resolve === undefined || !src.includes("this") && THIS_ONLY_RESOLVERS.has(resolve);
    if (cacheable) {
      const cached = stringDefCache.get(src);
      if (cached)
        return cached;
    }
    const pipeIndex = src.indexOf("|>");
    if (pipeIndex >= 0) {
      const input = src.slice(0, pipeIndex).trim();
      const output = src.slice(pipeIndex + 2).trim();
      if (input.length === 0 || output.length === 0) {
        throw new OmpTypeError(`pipe expression requires operands in "${src}"`);
      }
      const parsedInput = parseStringDef(input, resolve);
      if (parsedInput.hasDefault) {
        throw new OmpTypeError(`unexpected pipe expression after default in "${src}"`);
      }
      const parsed = {
        ir: {
          k: "morph",
          input: parsedInput.ir,
          fn: (value) => value,
          out: parseStringDef(output, resolve).ir
        },
        hasDefault: false,
        optional: false
      };
      if (cacheable && stringDefCache.size < STRING_DEF_CACHE_MAX)
        stringDefCache.set(src, parsed);
      return parsed;
    }
    let ir = parseLiteralUnion(src) ?? parseRegexExec(src) ?? parseGeneric(src, resolve);
    if (ir === undefined && src.startsWith("`") && src.endsWith("`")) {
      ir = templateIR(src.slice(1, -1));
    }
    const parsed = ir === undefined ? new StrParser(src, resolve).parseTop() : { ir, hasDefault: false, optional: false };
    if (cacheable && stringDefCache.size < STRING_DEF_CACHE_MAX)
      stringDefCache.set(src, parsed);
    return parsed;
  }
  function flip(op) {
    switch (op) {
      case "<":
        return ">";
      case "<=":
        return ">=";
      case ">":
        return "<";
      default:
        return "<=";
    }
  }
  function applyEquality(node, value, src) {
    if (node.k === "union") {
      return { k: "union", members: node.members.map((member) => applyEquality(member, value, src)) };
    }
    if (value instanceof Date) {
      if (!acceptsDate(node))
        throw new OmpTypeError(`Date equality requires Date in "${src}"`);
      return { k: "lit", v: value };
    }
    if (node.k === "number" && typeof value === "number")
      return { k: "lit", v: value };
    if (node.k === "bigint" && typeof value === "bigint")
      return { k: "lit", v: value };
    if ((node.k === "string" || node.k === "array") && typeof value === "number") {
      if (!Number.isInteger(value) || value < 0) {
        throw new OmpTypeError(`exact length must be a non-negative integer in "${src}"`);
      }
      return { ...node, min: value, max: value };
    }
    throw new OmpTypeError(`equality literal is incompatible with ${node.k} in "${src}"`);
  }
  function applyBound(node, op, value, src) {
    if (node.k === "alias")
      return applyBound(node.resolve(), op, value, src);
    if (node.k === "refine" && !(value instanceof Date)) {
      return { ...node, base: applyBound(node.base, op, value, src) };
    }
    if (node.k === "union") {
      const kinds = new Set(node.members.map(boundKind));
      if (kinds.size !== 1)
        throw new OmpTypeError(`cannot apply one bound to multiple bound kinds in "${src}"`);
      return { k: "union", members: node.members.map((member) => applyBound(member, op, value, src)) };
    }
    if (!(value instanceof Date) && acceptsDate(node)) {
      return applyBound(node, op, new Date(value), src);
    }
    if (value instanceof Date) {
      if (!acceptsDate(node))
        throw new OmpTypeError(`date bound requires Date in "${src}"`);
      const limit = value.valueOf();
      const relation = op === ">=" ? "on or after" : op === ">" ? "later than" : op === "<=" ? "on or before" : "earlier than";
      return {
        k: "refine",
        base: node,
        pred: (input) => {
          if (!(input instanceof Date))
            return false;
          const time = input.valueOf();
          return op === ">=" ? time >= limit : op === ">" ? time > limit : op === "<=" ? time <= limit : time < limit;
        },
        expected: `a Date ${relation} ${value.toISOString()}`
      };
    }
    if (node.k === "number") {
      const bounded = { ...node };
      switch (op) {
        case ">=":
          bounded.min = value;
          bounded.xmin = false;
          break;
        case ">":
          bounded.min = value;
          bounded.xmin = true;
          break;
        case "<=":
          bounded.max = value;
          bounded.xmax = false;
          break;
        case "<":
          bounded.max = value;
          bounded.xmax = true;
          break;
      }
      if (bounded.min !== undefined && bounded.max !== undefined && (bounded.min > bounded.max || bounded.min === bounded.max && (bounded.xmin || bounded.xmax))) {
        throw new OmpTypeError(`numeric range is unsatisfiable in "${src}"`);
      }
      return bounded;
    }
    if (node.k === "string" || node.k === "array") {
      if (!Number.isInteger(value) || value < 0) {
        throw new OmpTypeError(`length bound must be a non-negative integer in "${src}"`);
      }
      const bounded = { ...node };
      switch (op) {
        case ">=":
          bounded.min = value;
          break;
        case ">":
          bounded.min = value + 1;
          break;
        case "<=":
          bounded.max = value;
          break;
        case "<":
          bounded.max = value - 1;
          break;
      }
      if (bounded.min !== undefined && bounded.max !== undefined && bounded.min > bounded.max || (bounded.max ?? 0) < 0) {
        throw new OmpTypeError(`length range is unsatisfiable in "${src}"`);
      }
      return bounded;
    }
    throw new OmpTypeError(`cannot bound ${node.k} in "${src}"`);
  }
  function acceptsDate(node) {
    return node.k === "instance" && node.ctor === Date || node.k === "refine" && acceptsDate(node.base);
  }
  function isEmbedded(def) {
    return (typeof def === "function" || typeof def === "object" && def !== null) && IR_BRAND in def;
  }
  function embed(schema) {
    if (schema.hasSteps)
      return { k: "sub", schema, desc: schema.description, descAuto: schema.ir.desc === undefined };
    if (schema.description !== undefined && schema.ir.desc === undefined) {
      return { ...schema.ir, desc: schema.description, descAuto: true };
    }
    return schema.ir;
  }
  function boundKind(node) {
    if (node.k === "number")
      return "number";
    if (node.k === "string" || node.k === "array")
      return "length";
    if (acceptsDate(node))
      return "date";
    return;
  }
  function isCallback(value) {
    return typeof value === "function";
  }
  function isConstructor(value) {
    return typeof value === "function" && value.prototype !== undefined;
  }
  function parseTupleItem(def, resolve) {
    if (Array.isArray(def) && def.length === 2 && def[1] === "?") {
      return { val: parseDef(def[0], resolve), opt: true };
    }
    if (Array.isArray(def) && def.length === 3 && def[1] === "=") {
      return {
        val: parseDef(def[0], resolve),
        opt: true,
        def: def[2],
        defFactory: typeof def[2] === "function",
        hasDefault: true
      };
    }
    if (typeof def === "string") {
      const parsed = parseStringDef(def, resolve);
      return {
        val: parsed.ir,
        opt: parsed.optional || parsed.hasDefault,
        def: parsed.def,
        hasDefault: parsed.hasDefault
      };
    }
    return { val: parseDef(def, resolve), opt: false };
  }
  function cloneTuple(tuple) {
    return {
      ...tuple,
      prefix: tuple.prefix.map((item) => ({ ...item })),
      postfix: [...tuple.postfix]
    };
  }
  function hasOptionalPrefix(tuple) {
    return tuple.prefix.some((item) => item.opt || item.hasDefault === true);
  }
  function appendTupleItem(tuple, item) {
    if (tuple.variadic !== undefined) {
      if (item.opt || item.hasDefault) {
        throw new OmpTypeError("An optional element may not follow a variadic element");
      }
      if (hasOptionalPrefix(tuple)) {
        throw new OmpTypeError("A postfix required element cannot follow an optional or defaultable element");
      }
      tuple.postfix.push(item.val);
      return;
    }
    if (item.hasDefault && tuple.prefix.some((prefixItem) => prefixItem.opt && !prefixItem.hasDefault)) {
      throw new OmpTypeError("A defaultable element may not follow an optional element without a default");
    }
    if (hasOptionalPrefix(tuple) && !item.opt) {
      throw new OmpTypeError("required tuple elements cannot follow optional elements");
    }
    tuple.prefix.push(item);
  }
  function appendTuple(target, spread) {
    if (target.variadic !== undefined && spread.variadic !== undefined) {
      throw new OmpTypeError("a tuple may have one spread followed by an array definition");
    }
    for (const item of spread.prefix)
      appendTupleItem(target, { ...item });
    if (spread.variadic !== undefined) {
      target.variadic = spread.variadic;
    }
    for (const item of spread.postfix)
      appendTupleItem(target, { val: item, opt: false });
  }
  function spreadAlternatives(spread) {
    if (spread.k === "alias")
      return spreadAlternatives(spread.resolve());
    if (spread.k === "sub")
      return spreadAlternatives(spread.schema.ir);
    if (spread.k === "union")
      return spread.members.flatMap(spreadAlternatives);
    if (spread.k === "array")
      return [{ k: "tuple", prefix: [], variadic: spread.el, postfix: [] }];
    if (spread.k === "tuple")
      return [spread];
    throw new OmpTypeError("tuple spread element must be an array");
  }
  function parseTuple(def, resolve) {
    let branches = [{ k: "tuple", prefix: [], postfix: [] }];
    for (let index = 0;index < def.length; index++) {
      if (def[index] === "...") {
        if (index + 1 >= def.length) {
          throw new OmpTypeError("a tuple may have one spread followed by an array definition");
        }
        const alternatives = spreadAlternatives(parseDef(def[++index], resolve));
        const distributed = [];
        for (const branch of branches) {
          for (const alternative of alternatives) {
            const next = cloneTuple(branch);
            appendTuple(next, alternative);
            distributed.push(next);
          }
        }
        branches = distributed;
        continue;
      }
      const item = parseTupleItem(def[index], resolve);
      for (const branch of branches)
        appendTupleItem(branch, { ...item });
    }
    return branches.length === 1 ? branches[0] : { k: "union", members: branches };
  }
  function keyOf(node) {
    if (node.k === "alias")
      return keyOf(node.resolve());
    if (node.k === "sub")
      return keyOf(node.schema.ir);
    if (node.k === "refine")
      return keyOf(node.base);
    if (node.k === "intersection") {
      const members = node.members.flatMap((member) => {
        const keys = keyOf(member);
        return keys.k === "union" ? keys.members : [keys];
      });
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    if (node.k === "object") {
      const members = node.props.map((prop) => ({ k: "lit", v: prop.key }));
      if (node.index !== undefined || (node.patternIndexes?.length ?? 0) > 0)
        members.push({ k: "string" });
      if (node.symbolIndex !== undefined)
        members.push({ k: "symbol" });
      if (members.length === 0)
        return { k: "never" };
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    if (node.k === "tuple")
      return { k: "number", int: true, min: 0 };
    if (node.k === "union") {
      if (node.members.length === 0)
        return { k: "never" };
      const literalSets = node.members.map((member) => {
        const keyed = keyOf(member);
        const literals = keyed.k === "union" ? keyed.members : [keyed];
        const keys = new Set;
        for (const literal of literals) {
          if (literal.k === "lit" && (typeof literal.v === "string" || typeof literal.v === "number" || typeof literal.v === "symbol")) {
            keys.add(literal.v);
          }
        }
        return keys;
      });
      const common = [...literalSets[0]].filter((key) => literalSets.slice(1).every((keys) => keys.has(key)));
      if (common.length === 0)
        throw new OmpTypeError("keyof operand must be an object");
      const members = common.map((value) => ({ k: "lit", v: value }));
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    throw new OmpTypeError("keyof operand must be an object");
  }
  function parseArrayExpression(def, resolve) {
    if (def.length === 2 && def[1] === "[]")
      return { k: "array", el: parseDef(def[0], resolve) };
    if (def.length === 2 && def[0] === "keyof")
      return keyOf(parseDef(def[1], resolve));
    if (def[0] === "instanceof") {
      const members = [];
      for (let index = 1;index < def.length; index++) {
        const ctor = def[index];
        if (!isConstructor(ctor))
          throw new OmpTypeError("instanceof operands must be constructors");
        members.push({
          k: "instance",
          ctor,
          expected: ctor === Error ? "an Error" : `an instance of ${ctor.name || "the constructor"}`
        });
      }
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    if (def[0] === "===") {
      const members = def.slice(1).map((value) => ({ k: "lit", v: value }));
      if (members.length === 0)
        return { k: "never" };
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    if (def.length >= 3 && def[1] === "|") {
      return { k: "union", members: [parseDef(def[0], resolve), parseDef(def[2], resolve)] };
    }
    if (def.length >= 3 && def[1] === "&") {
      return { k: "intersection", members: [parseDef(def[0], resolve), parseDef(def[2], resolve)] };
    }
    if (def.length === 3 && def[1] === "=>") {
      if (!isCallback(def[2]))
        throw new OmpTypeError("morph operator requires a function");
      return { k: "morph", input: parseDef(def[0], resolve), fn: def[2] };
    }
    if (def.length === 3 && def[1] === "|>") {
      return { k: "morph", input: parseDef(def[0], resolve), fn: (value) => value, out: parseDef(def[2], resolve) };
    }
    if (def.length === 3 && def[1] === ":") {
      if (!isCallback(def[2]))
        throw new OmpTypeError("narrow operator requires a predicate");
      const predicate = def[2];
      const name = predicate.name;
      const expected = name.length === 0 ? "valid according to an anonymous predicate" : `valid according to ${name}`;
      return {
        k: "refine",
        base: parseDef(def[0], resolve),
        pred: (value) => {
          let errors;
          const error = (input) => {
            const detail = typeof input === "string" ? { expected: input } : input;
            const next = OmpErrors.single([...detail.path ?? detail.relativePath ?? []], detail.expected, value, {
              preserveActual: true,
              ...Object.hasOwn(detail, "actual") ? { actual: String(detail.actual) } : {}
            });
            if (errors)
              errors.append(next);
            else
              errors = next;
            return next;
          };
          const result = predicate(value, { error, reject: error });
          return errors ?? (result instanceof OmpErrors ? result : result === true);
        },
        expected
      };
    }
    if (def.length >= 3 && def[1] === "@") {
      const base = parseDef(def[0], resolve);
      const meta = def[2];
      if (typeof meta === "string")
        return { ...base, desc: meta, cfg: { ...base.cfg, expected: meta } };
      if (typeof meta === "object" && meta !== null) {
        const config = meta;
        return {
          ...base,
          cfg: {
            ...typeof config.description === "string" ? { expected: config.description } : {},
            ...config
          },
          ...typeof config.description === "string" ? { desc: config.description } : {}
        };
      }
      return base;
    }
    return parseTuple(def, resolve);
  }
  function isObjectDefinition(def) {
    return typeof def === "object" && def !== null && !Array.isArray(def) && !(def instanceof RegExp) && !(def instanceof Date);
  }
  function spreadObjectOf(ir) {
    if (ir.k === "alias")
      return spreadObjectOf(ir.resolve());
    if (ir.k === "sub")
      return spreadObjectOf(ir.schema.ir);
    if (ir.k === "refine")
      return spreadObjectOf(ir.base);
    if (ir.k === "anyobject")
      return { k: "object", props: [], extras: "keep" };
    if (ir.k === "object")
      return ir;
    if (ir.k !== "intersection")
      return;
    let result = { k: "object", props: [], extras: "keep" };
    for (const member of ir.members) {
      const object = spreadObjectOf(member);
      if (object === undefined)
        return;
      result = mergeObjectIR(result, object);
    }
    return result;
  }
  function indexKeyKind(key, value, props, indexes) {
    if (key.k === "alias")
      return indexKeyKind(key.resolve(), value, props, indexes);
    if (key.k === "union") {
      for (const member of key.members)
        indexKeyKind(member, value, props, indexes);
      return;
    }
    if (key.k === "lit" && (typeof key.v === "string" || typeof key.v === "symbol")) {
      props.push({ key: key.v, opt: false, val: value });
      return;
    }
    if (key.k === "string") {
      indexes.string = value;
      return;
    }
    if (key.k === "symbol") {
      indexes.symbol = value;
      return;
    }
    if (key.k === "refine" && key.base.k === "string") {
      indexes.patterns.push({ key, val: value });
      return;
    }
    throw new OmpTypeError(`indexed key definition must resolve to a string or symbol (was ${expectedOf(key)})`);
  }
  function addObjectProp(props, spreadKeys, prop) {
    if (spreadKeys === undefined) {
      props.push(prop);
      return;
    }
    const previous = props.findIndex((candidate) => candidate.key === prop.key);
    if (previous < 0) {
      props.push(prop);
      return;
    }
    if (!spreadKeys.delete(prop.key))
      throw new OmpTypeError(`duplicate object key ${String(prop.key)}`);
    props[previous] = prop;
  }
  function parseObjectDefinition(def, resolve) {
    const props = [];
    let spreadKeys;
    let normalizedKey;
    let normalizedKeys;
    let indexes;
    let extras = "keep";
    let simple = true;
    for (const originalKey in def) {
      if (!Object.hasOwn(def, originalKey))
        continue;
      const val = def[originalKey];
      if (originalKey === "+") {
        if (val === "reject" || val === "delete") {
          extras = val;
          if (val === "delete")
            simple = false;
        } else if (val === "ignore")
          extras = "keep";
        else
          throw new OmpTypeError(`bad "+" value ${String(val)}`);
        continue;
      }
      if (originalKey === "...") {
        const parsed = parseDef(val, resolve);
        const spread = spreadObjectOf(parsed);
        if (spread === undefined) {
          throw new OmpTypeError(`object spread must resolve to an object literal (was ${expectedOf(parsed)})`);
        }
        if (simple && !isSimpleIR(spread))
          simple = false;
        spreadKeys ??= new Set;
        for (const prop of spread.props) {
          const previous = props.findIndex((candidate) => candidate.key === prop.key);
          if (previous < 0)
            props.push(prop);
          else
            props[previous] = prop;
          spreadKeys.add(prop.key);
        }
        if (spread.index !== undefined || spread.symbolIndex !== undefined || spread.patternIndexes !== undefined) {
          const objectIndexes = indexes ?? { patterns: [] };
          indexes = objectIndexes;
          objectIndexes.string ??= spread.index;
          objectIndexes.symbol ??= spread.symbolIndex;
          if (spread.patternIndexes !== undefined)
            objectIndexes.patterns.push(...spread.patternIndexes);
        }
        if (spread.extras !== "keep")
          extras = spread.extras;
        continue;
      }
      if (typeof originalKey === "string" && originalKey.startsWith("[") && originalKey.endsWith("]")) {
        let value;
        if (typeof val === "string") {
          const parsed = parseStringDef(val, resolve);
          if (parsed.hasDefault)
            throw new OmpTypeError("index signatures cannot specify a default");
          value = parsed.ir;
        } else {
          if (Array.isArray(val) && val.length === 3 && val[1] === "=") {
            throw new OmpTypeError("index signatures cannot specify a default");
          }
          value = parseDef(val, resolve);
          if (isEmbedded(val) && val.hasDefault) {
            throw new OmpTypeError("index signatures cannot specify a default");
          }
        }
        const keyDefinition = originalKey.slice(1, -1);
        const regex = /^\/((?:\\.|[^\\/])*)\/([dgimsuvy]*)$/.exec(keyDefinition);
        let key;
        if (regex === null) {
          key = parseDef(keyDefinition, resolve);
        } else {
          try {
            key = patternIR(new RegExp(regex[1], regex[2]));
          } catch {
            throw new OmpTypeError(`invalid index signature pattern ${keyDefinition}`);
          }
        }
        const objectIndexes = indexes ?? { patterns: [] };
        indexes = objectIndexes;
        indexKeyKind(key, value, props, objectIndexes);
        if (simple && (!isSimpleIR(key) || !isSimpleIR(value)))
          simple = false;
        continue;
      }
      const escapedOptional = typeof originalKey === "string" && originalKey.endsWith("\\?");
      const escapedMeta = typeof originalKey === "string" && (originalKey === "\\+" || originalKey === "\\..." || originalKey.startsWith("\\["));
      const rawKey = escapedOptional ? `${originalKey.slice(0, -2)}?` : escapedMeta ? originalKey.slice(1) : originalKey;
      const opt = typeof rawKey === "string" && !escapedOptional && !escapedMeta && rawKey.endsWith("?");
      const key = opt ? rawKey.slice(0, -1) : rawKey;
      let prop;
      if (typeof val === "string") {
        const parsed = parseStringDef(val, resolve);
        prop = { key, opt: opt || parsed.optional, val: parsed.ir };
        if (parsed.hasDefault) {
          prop.def = parsed.def;
          prop.hasDefault = true;
        }
      } else if (Array.isArray(val) && val.length === 2 && val[1] === "?") {
        prop = { key, opt: true, val: parseDef(val[0], resolve) };
      } else if (Array.isArray(val) && val.length === 3 && val[1] === "=") {
        prop = {
          key,
          opt,
          val: parseDef(val[0], resolve),
          def: val[2],
          defFactory: typeof val[2] === "function",
          hasDefault: true
        };
      } else if (isEmbedded(val)) {
        prop = val.hasDefault ? {
          key,
          opt,
          val: embed(val),
          def: val.hasDefaultOutput ? val.defaultOutput : val.defaultValue,
          defFactory: typeof val.defaultValue === "function",
          hasDefault: true,
          defValidated: val.hasDefaultOutput
        } : { key, opt, val: embed(val) };
      } else {
        prop = {
          key,
          opt,
          val: isObjectDefinition(val) ? parseObjectDefinition(val, resolve) : parseDef(val, resolve)
        };
      }
      if (key !== originalKey) {
        if (!spreadKeys?.has(key) && props.some((candidate) => candidate.key === key)) {
          throw new OmpTypeError(`duplicate object key ${String(key)}`);
        }
        if (normalizedKey === undefined)
          normalizedKey = key;
        else {
          normalizedKeys ??= [normalizedKey];
          normalizedKeys.push(key);
        }
      } else if (!spreadKeys?.has(key) && (key === normalizedKey || normalizedKeys?.includes(key))) {
        throw new OmpTypeError(`duplicate object key ${String(key)}`);
      }
      if (opt && prop.hasDefault)
        throw new OmpTypeError(`optional key ${String(key)} cannot specify a default`);
      if (simple && (prop.hasDefault || !isSimpleIR(prop.val)))
        simple = false;
      addObjectProp(props, spreadKeys, prop);
    }
    for (const key of Object.getOwnPropertySymbols(def)) {
      if (!Object.prototype.propertyIsEnumerable.call(def, key))
        continue;
      const val = def[key];
      let prop;
      if (typeof val === "string") {
        const parsed = parseStringDef(val, resolve);
        prop = { key, opt: parsed.optional, val: parsed.ir };
        if (parsed.hasDefault) {
          prop.def = parsed.def;
          prop.hasDefault = true;
        }
      } else if (Array.isArray(val) && val.length === 2 && val[1] === "?") {
        prop = { key, opt: true, val: parseDef(val[0], resolve) };
      } else if (Array.isArray(val) && val.length === 3 && val[1] === "=") {
        prop = {
          key,
          opt: false,
          val: parseDef(val[0], resolve),
          def: val[2],
          defFactory: typeof val[2] === "function",
          hasDefault: true
        };
      } else if (isEmbedded(val)) {
        prop = val.hasDefault ? {
          key,
          opt: false,
          val: embed(val),
          def: val.hasDefaultOutput ? val.defaultOutput : val.defaultValue,
          defFactory: typeof val.defaultValue === "function",
          hasDefault: true,
          defValidated: val.hasDefaultOutput
        } : { key, opt: false, val: embed(val) };
      } else {
        prop = {
          key,
          opt: false,
          val: isObjectDefinition(val) ? parseObjectDefinition(val, resolve) : parseDef(val, resolve)
        };
      }
      if (simple && (prop.hasDefault || !isSimpleIR(prop.val)))
        simple = false;
      addObjectProp(props, spreadKeys, prop);
    }
    const object = {
      k: "object",
      props,
      index: indexes?.string,
      symbolIndex: indexes?.symbol,
      patternIndexes: indexes === undefined || indexes.patterns.length === 0 ? undefined : indexes.patterns,
      extras
    };
    object[kSimple] = simple;
    object[kSimpleOwner] = object;
    return object;
  }
  function parseDef(def, resolve) {
    if (typeof def === "string") {
      const parsed = parseStringDef(def, resolve);
      if (parsed.hasDefault) {
        throw new OmpTypeError("A default may only be specified for an object property or tuple element");
      }
      if (parsed.optional) {
        throw new OmpTypeError(`optional "?" marker is only valid on object property values`);
      }
      return parsed.ir;
    }
    if (Array.isArray(def)) {
      if (def.length === 3 && def[1] === "=") {
        throw new OmpTypeError("A default may only be specified for an object property or tuple element");
      }
      return parseArrayExpression(def, resolve);
    }
    if (def instanceof RegExp)
      return patternIR(def);
    if (def instanceof Date)
      return { k: "lit", v: def };
    if (isEmbedded(def))
      return embed(def);
    if (typeof def === "function") {
      const resolved = Reflect.apply(def, undefined, []);
      if (!isEmbedded(resolved)) {
        throw new OmpTypeError(`thunk must return a Type (was ${typeof resolved})`);
      }
      return embed(resolved);
    }
    if (isObjectDefinition(def))
      return parseObjectDefinition(def, resolve);
    throw new OmpTypeError(`unsupported definition ${String(def)} (was ${typeof def})`);
  }
  function isSimpleIR(ir) {
    const cached = ir[kSimpleOwner] === ir ? ir[kSimple] : undefined;
    if (cached !== undefined)
      return cached;
    const simple = scanSimpleIR(ir);
    ir[kSimple] = simple;
    ir[kSimpleOwner] = ir;
    return simple;
  }
  function scanSimpleIR(ir) {
    switch (ir.k) {
      case "intersection":
      case "morph":
      case "sub":
      case "alias":
        return false;
      case "refine":
        return scanSimpleIR(ir.base);
      case "union":
        if (ir.members.length < 2)
          return false;
        if (ir.members.length === 2 && ir.members.every((member) => member.k === "lit" && typeof member.v === "boolean")) {
          return false;
        }
        for (let index = 0;index < ir.members.length; index++) {
          const member = ir.members[index];
          if (member.k !== "lit" || member.v !== null && (typeof member.v === "object" || typeof member.v === "function")) {
            return false;
          }
          for (let previous = 0;previous < index; previous++) {
            const candidate = ir.members[previous];
            if (candidate.k === "lit" && candidate.v === member.v)
              return false;
          }
        }
        return true;
      case "array":
        return scanSimpleIR(ir.el);
      case "tuple":
        for (const item of ir.prefix) {
          if (item.hasDefault || !scanSimpleIR(item.val))
            return false;
        }
        if (ir.variadic !== undefined && !scanSimpleIR(ir.variadic))
          return false;
        for (const item of ir.postfix)
          if (!scanSimpleIR(item))
            return false;
        return true;
      case "object":
        if (ir.extras === "delete")
          return false;
        for (const prop of ir.props) {
          if (prop.hasDefault || !scanSimpleIR(prop.val))
            return false;
        }
        if (ir.index !== undefined && !scanSimpleIR(ir.index))
          return false;
        if (ir.symbolIndex !== undefined && !scanSimpleIR(ir.symbolIndex))
          return false;
        if (ir.patternIndexes !== undefined) {
          for (const pattern of ir.patternIndexes) {
            if (!scanSimpleIR(pattern.key) || !scanSimpleIR(pattern.val))
              return false;
          }
        }
        return true;
      default:
        return true;
    }
  }
  function hasMorph(ir) {
    const cached = ir[kMorphOwner] === ir ? ir[kMorph] : undefined;
    if (cached !== undefined)
      return cached;
    const result = scanMorph(ir);
    ir[kMorph] = result;
    ir[kMorphOwner] = ir;
    return result;
  }
  function scanMorph(ir, activeAliases) {
    const cached = ir[kMorphOwner] === ir ? ir[kMorph] : undefined;
    if (cached !== undefined)
      return cached;
    let result = false;
    switch (ir.k) {
      case "sub":
      case "morph":
        result = true;
        break;
      case "alias": {
        if (activeAliases?.has(ir))
          return false;
        const aliases = activeAliases ?? new Set;
        aliases.add(ir);
        result = scanMorph(ir.resolve(), aliases);
        aliases.delete(ir);
        return result;
      }
      case "object":
        result = ir.extras === "delete";
        for (let index = 0;!result && index < ir.props.length; index++) {
          const prop = ir.props[index];
          result = prop.hasDefault === true || scanMorph(prop.val, activeAliases);
        }
        if (!result && ir.index !== undefined)
          result = scanMorph(ir.index, activeAliases);
        if (!result && ir.symbolIndex !== undefined)
          result = scanMorph(ir.symbolIndex, activeAliases);
        if (!result && ir.patternIndexes !== undefined) {
          for (const pattern of ir.patternIndexes) {
            if (scanMorph(pattern.val, activeAliases)) {
              result = true;
              break;
            }
          }
        }
        break;
      case "array":
        result = scanMorph(ir.el, activeAliases);
        break;
      case "union":
      case "intersection":
        for (const member of ir.members) {
          if (scanMorph(member, activeAliases)) {
            result = true;
            break;
          }
        }
        break;
      case "refine":
        result = scanMorph(ir.base, activeAliases);
        break;
      case "tuple":
        for (const item of ir.prefix) {
          if (item.hasDefault === true || scanMorph(item.val, activeAliases)) {
            result = true;
            break;
          }
        }
        if (!result && ir.variadic !== undefined)
          result = scanMorph(ir.variadic, activeAliases);
        if (!result) {
          for (const item of ir.postfix) {
            if (scanMorph(item, activeAliases)) {
              result = true;
              break;
            }
          }
        }
        break;
    }
    return result;
  }
  function hasAlias(ir) {
    const cached = ir[kAliasOwner] === ir ? ir[kAlias] : undefined;
    if (cached !== undefined)
      return cached;
    const result = scanAlias(ir);
    ir[kAlias] = result;
    ir[kAliasOwner] = ir;
    return result;
  }
  function scanAlias(ir) {
    const cached = ir[kAliasOwner] === ir ? ir[kAlias] : undefined;
    if (cached !== undefined)
      return cached;
    switch (ir.k) {
      case "alias":
        return true;
      case "object":
        for (const prop of ir.props)
          if (scanAlias(prop.val))
            return true;
        if (ir.index !== undefined && scanAlias(ir.index))
          return true;
        if (ir.symbolIndex !== undefined && scanAlias(ir.symbolIndex))
          return true;
        if (ir.patternIndexes !== undefined) {
          for (const pattern of ir.patternIndexes) {
            if (scanAlias(pattern.key) || scanAlias(pattern.val))
              return true;
          }
        }
        return false;
      case "array":
        return scanAlias(ir.el);
      case "tuple":
        for (const item of ir.prefix)
          if (scanAlias(item.val))
            return true;
        if (ir.variadic !== undefined && scanAlias(ir.variadic))
          return true;
        for (const item of ir.postfix)
          if (scanAlias(item))
            return true;
        return false;
      case "union":
      case "intersection":
        for (const member of ir.members)
          if (scanAlias(member))
            return true;
        return false;
      case "refine":
        return scanAlias(ir.base);
      case "morph":
        return scanAlias(ir.input) || ir.out !== undefined && scanAlias(ir.out);
      default:
        return false;
    }
  }
  function expectedOf(ir) {
    if (ir.desc !== undefined)
      return ir.desc;
    switch (ir.k) {
      case "unknown":
        return "unknown";
      case "null":
        return "null";
      case "undefined":
        return "undefined";
      case "boolean":
        return "boolean";
      case "bigint":
        return "a bigint";
      case "symbol":
        return "a symbol";
      case "never":
        return "never";
      case "anyobject":
        return "an object";
      case "string": {
        let out = ir.url ? "a URL string" : "a string";
        if (ir.min !== undefined && ir.max !== undefined)
          out += ` (length ${ir.min} to ${ir.max})`;
        else if (ir.min !== undefined)
          out += ` (length at least ${ir.min})`;
        else if (ir.max !== undefined)
          out += ` (length at most ${ir.max})`;
        return out;
      }
      case "number": {
        let out = ir.int ? "an integer" : "a number";
        if (ir.min !== undefined)
          out += ` ${ir.xmin ? "more than" : "at least"} ${ir.min}`;
        if (ir.max !== undefined)
          out += `${ir.min !== undefined ? " and" : ""} ${ir.xmax ? "less than" : "at most"} ${ir.max}`;
        if (ir.divisor !== undefined)
          out += ` divisible by ${ir.divisor}`;
        return out;
      }
      case "lit":
        return ir.v instanceof Date ? `the date ${ir.v.toISOString()}` : typeof ir.v === "string" ? JSON.stringify(ir.v) : String(ir.v);
      case "union": {
        if (ir.members.length === 0)
          return "";
        const first = expectedOf(ir.members[0]);
        if (ir.members.length === 1)
          return first;
        const second = expectedOf(ir.members[1]);
        if (ir.members.length === 2)
          return first === second ? first : `${first} or ${second}`;
        const expectations = first === second ? [first] : [first, second];
        for (let i = 2;i < ir.members.length; i++) {
          const expected = expectedOf(ir.members[i]);
          if (!expectations.includes(expected))
            expectations.push(expected);
        }
        return expectations.join(" or ");
      }
      case "intersection":
        return ir.members.map(expectedOf).join(" and ");
      case "array":
        return "an array";
      case "tuple":
        return "a tuple";
      case "object":
        return "an object";
      case "instance":
        return ir.expected;
      case "refine":
        return ir.expected;
      case "morph":
        return expectedOf(ir.input);
      case "alias":
        return ir.name === "this" ? expectedOf(ir.resolve()) : ir.name;
      case "sub":
        return ir.desc ?? ir.schema.description ?? expectedOf(ir.schema.ir);
    }
  }

  // ../build/upstream/oh-my-pi/packages/omptype/src/interp.ts
  var own = Object.prototype.hasOwnProperty;
  function materializeDefault(payload) {
    if (payload === null || typeof payload !== "object")
      return payload;
    if (payload instanceof Date)
      return new Date(payload);
    return structuredClone(payload);
  }
  var activeVisits;
  var activeChecks;
  function walk(ir, value, path = []) {
    const previousVisits = activeVisits;
    const previousChecks = activeChecks;
    activeVisits = undefined;
    activeChecks = undefined;
    try {
      return visit(ir, value, path);
    } finally {
      activeVisits = previousVisits;
      activeChecks = previousChecks;
    }
  }
  function fail(path, expected, data) {
    const storedPath = path.length === 0 ? undefined : path.length === 1 ? path[0] : [...path];
    return new OmpErrors(storedPath, expected, data);
  }
  function checks(ir, v) {
    if (typeof v !== "object" || v === null || !hasAlias(ir))
      return checkNode(ir, v);
    activeChecks ??= new WeakMap;
    const visits = activeChecks;
    let visited = visits.get(v);
    if (visited?.has(ir))
      return true;
    if (visited === undefined) {
      visited = new Set;
      visits.set(v, visited);
    }
    visited.add(ir);
    try {
      return checkNode(ir, v);
    } finally {
      visited.delete(ir);
    }
  }
  function checkNode(ir, v) {
    switch (ir.k) {
      case "unknown":
        return true;
      case "null":
        return v === null;
      case "undefined":
        return v === undefined;
      case "boolean":
        return typeof v === "boolean";
      case "bigint":
        return typeof v === "bigint";
      case "symbol":
        return typeof v === "symbol";
      case "never":
        return false;
      case "anyobject":
        return typeof v === "object" && v !== null;
      case "string":
        return typeof v === "string" && (ir.min === undefined || v.length >= ir.min) && (ir.max === undefined || v.length <= ir.max) && (!ir.url || URL.canParse(v));
      case "number":
        if (typeof v !== "number")
          return false;
        return (ir.int ? Number.isInteger(v) : Number.isFinite(v)) && (ir.divisor === undefined || v % ir.divisor === 0) && (ir.min === undefined || (ir.xmin ? v > ir.min : v >= ir.min)) && (ir.max === undefined || (ir.xmax ? v < ir.max : v <= ir.max));
      case "lit":
        return ir.v instanceof Date ? v instanceof Date && v.valueOf() === ir.v.valueOf() : v === ir.v;
      case "union":
        return ir.members.some((m) => checks(m, v));
      case "intersection":
        return ir.members.every((member) => checks(member, v));
      case "array": {
        if (!Array.isArray(v))
          return false;
        if (ir.min !== undefined && v.length < ir.min)
          return false;
        if (ir.max !== undefined && v.length > ir.max)
          return false;
        for (const element of v)
          if (!checks(ir.el, element))
            return false;
        return true;
      }
      case "tuple": {
        if (!Array.isArray(v))
          return false;
        let required = ir.postfix.length;
        for (const item of ir.prefix)
          if (!item.opt && !item.hasDefault)
            required++;
        if (v.length < required)
          return false;
        if (ir.variadic === undefined && v.length > ir.prefix.length + ir.postfix.length)
          return false;
        const postfixStart = v.length - ir.postfix.length;
        const prefixCount = Math.min(ir.prefix.length, postfixStart);
        for (let index = 0;index < prefixCount; index++) {
          if (!checks(ir.prefix[index].val, v[index]))
            return false;
        }
        for (let index = prefixCount;index < ir.prefix.length; index++) {
          const item = ir.prefix[index];
          if (!item.opt && !item.hasDefault)
            return false;
        }
        if (ir.variadic !== undefined) {
          for (let index = prefixCount;index < postfixStart; index++) {
            if (!checks(ir.variadic, v[index]))
              return false;
          }
        }
        for (let index = 0;index < ir.postfix.length; index++) {
          if (!checks(ir.postfix[index], v[postfixStart + index]))
            return false;
        }
        return true;
      }
      case "object": {
        if (typeof v !== "object" || v === null)
          return false;
        const rec = v;
        for (const p of ir.props) {
          const present = p.key in rec;
          if (!present) {
            if (!p.opt && !p.hasDefault)
              return false;
            continue;
          }
          if (!checks(p.val, rec[p.key]))
            return false;
        }
        for (const key in rec) {
          if (!own.call(rec, key))
            continue;
          if (ir.index !== undefined && !checks(ir.index, rec[key]))
            return false;
          let patternMatched = false;
          if (ir.patternIndexes !== undefined) {
            for (const pattern of ir.patternIndexes) {
              if (!checks(pattern.key, key))
                continue;
              patternMatched = true;
              if (!checks(pattern.val, rec[key]))
                return false;
            }
          }
          if (ir.extras === "reject" && ir.index === undefined && !patternMatched && !ir.props.some((prop) => prop.key === key)) {
            return false;
          }
        }
        for (const key of Object.getOwnPropertySymbols(rec)) {
          if (!Object.prototype.propertyIsEnumerable.call(rec, key))
            continue;
          if (ir.symbolIndex !== undefined && !checks(ir.symbolIndex, rec[key]))
            return false;
          if (ir.extras === "reject" && ir.symbolIndex === undefined && !ir.props.some((prop) => prop.key === key)) {
            return false;
          }
        }
        return true;
      }
      case "instance":
        return v instanceof ir.ctor;
      case "refine":
        if (!checks(ir.base, v))
          return false;
        try {
          return ir.pred(v) === true;
        } catch {
          return false;
        }
      case "alias":
        return checks(ir.resolve(), v);
      case "morph":
        return checks(ir.input, v);
      case "sub":
        return !(ir.schema.run(v) instanceof OmpErrors);
    }
  }
  function visit(ir, v, path) {
    if (typeof v !== "object" || v === null || !hasAlias(ir))
      return visitFinish(ir, v, path);
    activeVisits ??= new WeakMap;
    const visits = activeVisits;
    let visited = visits.get(v);
    if (visited?.has(ir))
      return v;
    if (visited === undefined) {
      visited = new Set;
      visits.set(v, visited);
    }
    visited.add(ir);
    try {
      return visitFinish(ir, v, path);
    } finally {
      visited.delete(ir);
    }
  }
  function visitFinish(ir, v, path) {
    const out = visitNode(ir, v, path);
    if (!(out instanceof OmpErrors) || ir.cfg === undefined)
      return out;
    for (const error of out) {
      if (error.path.length !== path.length)
        return out;
    }
    return out.configure(ir.cfg);
  }
  function visitNode(ir, v, path) {
    switch (ir.k) {
      case "alias":
        return visit(ir.resolve(), v, path);
      case "refine": {
        const base = visit(ir.base, v, path);
        if (base instanceof OmpErrors)
          return base;
        try {
          const result = ir.pred(base);
          if (result instanceof OmpErrors)
            return path.length === 0 ? result : prefixAll(result, path);
          return result ? base : fail(path, ir.expected, base);
        } catch {
          return fail(path, ir.expected, base);
        }
      }
      case "morph": {
        const input = visit(ir.input, v, path);
        if (input instanceof OmpErrors)
          return input;
        const context = {
          error: (expected, data = input) => fail(path, expected, data),
          reject: (problem, data = input) => fail(path, problem, data)
        };
        const output = ir.fn(input, context);
        if (output instanceof OmpErrors)
          return output;
        return ir.out === undefined ? output : visit(ir.out, output, path);
      }
      case "intersection": {
        let output = v;
        for (const member of ir.members) {
          output = visit(member, output, path);
          if (output instanceof OmpErrors)
            return output;
        }
        return output;
      }
      case "sub": {
        const out = ir.schema.run(v, path);
        if (out instanceof OmpErrors) {
          return path.length === 0 ? out : prefixAll(out, path);
        }
        return out;
      }
      case "union": {
        for (const m of ir.members) {
          if (m.k !== "sub" && checks(m, v)) {
            if (hasMorph(m))
              break;
            return v;
          }
        }
        let targeted;
        let targetCount = 0;
        for (const member of ir.members) {
          if (member.k === "sub" || hasMorph(member)) {
            const out = visit(member, v, path);
            if (!(out instanceof OmpErrors))
              return out;
            if (kindMatches(unwrapBase(member), v)) {
              targetCount++;
              targeted ??= out;
            }
          }
        }
        if (targetCount === 1 && targeted !== undefined)
          return targeted;
        return ir.members.some(canRefineUnionFailure) ? unionFail(ir, v, path) : fail(path, expectedOf(ir), v);
      }
      case "array": {
        if (!Array.isArray(v))
          return fail(path, "an array", v);
        if (ir.min !== undefined && v.length < ir.min)
          return fail(path, `at least length ${ir.min}`, v.length);
        if (ir.max !== undefined && v.length > ir.max)
          return fail(path, `at most length ${ir.max}`, v.length);
        const morph = hasMorph(ir.el);
        const out = morph ? new Array(v.length) : v;
        let errors;
        for (let index = 0;index < v.length; index++) {
          path.push(index);
          const element = visit(ir.el, v[index], path);
          path.pop();
          if (element instanceof OmpErrors) {
            if (errors)
              errors.append(element);
            else
              errors = element;
          } else if (morph) {
            out[index] = element;
          }
        }
        return errors ?? out;
      }
      case "tuple": {
        if (!Array.isArray(v))
          return fail(path, "an array", v);
        let required = ir.postfix.length;
        for (const item of ir.prefix)
          if (!item.opt && !item.hasDefault)
            required++;
        if (v.length < required)
          return fail(path, `an array of at least length ${required}`, v);
        const maximum = ir.prefix.length + ir.postfix.length;
        if (ir.variadic === undefined && v.length > maximum) {
          return fail(path, `an array of at most length ${maximum}`, v);
        }
        const postfixStart = v.length - ir.postfix.length;
        const prefixCount = Math.min(ir.prefix.length, postfixStart);
        const morph = hasMorph(ir);
        const output = morph ? [...v] : v;
        let errors;
        for (let index = 0;index < prefixCount; index++) {
          path.push(index);
          const item = visit(ir.prefix[index].val, v[index], path);
          path.pop();
          if (item instanceof OmpErrors) {
            if (errors)
              errors.append(item);
            else
              errors = item;
          } else if (morph) {
            output[index] = item;
          }
        }
        for (let index = prefixCount;index < ir.prefix.length; index++) {
          const item = ir.prefix[index];
          if (item.hasDefault && morph) {
            const payload = item.def;
            if (item.defFactory && typeof payload === "function") {
              path.push(index);
              const resolved = visit(item.val, payload(), path);
              path.pop();
              if (resolved instanceof OmpErrors) {
                if (errors)
                  errors.append(resolved);
                else
                  errors = resolved;
              } else {
                output[index] = resolved;
              }
            } else {
              output[index] = materializeDefault(payload);
            }
          } else if (!item.opt) {
            path.push(index);
            const error = fail(path, expectedOf(item.val), MISSING);
            path.pop();
            if (errors)
              errors.append(error);
            else
              errors = error;
          }
        }
        if (ir.variadic !== undefined) {
          for (let index = prefixCount;index < postfixStart; index++) {
            path.push(index);
            const item = visit(ir.variadic, v[index], path);
            path.pop();
            if (item instanceof OmpErrors) {
              if (errors)
                errors.append(item);
              else
                errors = item;
            } else if (morph) {
              output[index] = item;
            }
          }
        }
        for (let index = 0;index < ir.postfix.length; index++) {
          const inputIndex = postfixStart + index;
          path.push(inputIndex);
          const item = visit(ir.postfix[index], v[inputIndex], path);
          path.pop();
          if (item instanceof OmpErrors) {
            if (errors)
              errors.append(item);
            else
              errors = item;
          } else if (morph) {
            output[inputIndex] = item;
          }
        }
        return errors ?? output;
      }
      case "object": {
        if (typeof v !== "object" || v === null)
          return fail(path, "an object", v);
        const rec = v;
        const morph = hasMorph(ir);
        let out;
        let errors;
        if (morph) {
          if (ir.extras === "delete" && ir.index === undefined && ir.symbolIndex === undefined && ir.patternIndexes === undefined) {
            out = {};
          } else {
            out = { ...rec };
          }
        }
        for (const p of ir.props) {
          if (!(p.key in rec)) {
            if (p.hasDefault && out) {
              const payload = p.def;
              if (p.defFactory && typeof payload === "function") {
                path.push(p.key);
                const resolved = visit(p.val, payload(), path);
                path.pop();
                if (resolved instanceof OmpErrors) {
                  if (errors)
                    errors.append(resolved);
                  else
                    errors = resolved;
                } else {
                  out[p.key] = resolved;
                }
              } else {
                out[p.key] = materializeDefault(payload);
              }
              continue;
            }
            if (p.opt || p.hasDefault)
              continue;
            path.push(p.key);
            const error = fail(path, expectedOf(p.val), MISSING);
            path.pop();
            if (errors)
              errors.append(error);
            else
              errors = error;
            continue;
          }
          path.push(p.key);
          const result = visit(p.val, rec[p.key], path);
          path.pop();
          if (result instanceof OmpErrors) {
            if (errors)
              errors.append(result);
            else
              errors = result;
          } else if (out) {
            out[p.key] = result;
          }
        }
        for (const key in rec) {
          if (!own.call(rec, key))
            continue;
          let indexed = false;
          if (ir.index !== undefined) {
            indexed = true;
            path.push(key);
            const result = visit(ir.index, rec[key], path);
            path.pop();
            if (result instanceof OmpErrors) {
              if (errors)
                errors.append(result);
              else
                errors = result;
            } else if (out) {
              out[key] = result;
            }
          }
          if (ir.patternIndexes !== undefined) {
            for (const pattern of ir.patternIndexes) {
              if (!checks(pattern.key, key))
                continue;
              indexed = true;
              path.push(key);
              const result = visit(pattern.val, rec[key], path);
              path.pop();
              if (result instanceof OmpErrors) {
                if (errors)
                  errors.append(result);
                else
                  errors = result;
              } else if (out) {
                out[key] = result;
              }
            }
          }
          if (ir.extras === "reject" && !indexed && !ir.props.some((prop) => prop.key === key)) {
            path.push(key);
            const error = fail(path, "removed", rec[key]);
            path.pop();
            if (errors)
              errors.append(error);
            else
              errors = error;
          }
        }
        for (const key of Object.getOwnPropertySymbols(rec)) {
          if (!Object.prototype.propertyIsEnumerable.call(rec, key))
            continue;
          if (ir.symbolIndex !== undefined) {
            path.push(key);
            const result = visit(ir.symbolIndex, rec[key], path);
            path.pop();
            if (result instanceof OmpErrors) {
              if (errors)
                errors.append(result);
              else
                errors = result;
            } else if (out) {
              out[key] = result;
            }
          } else if (ir.extras === "reject" && !ir.props.some((prop) => prop.key === key)) {
            path.push(key);
            const error = fail(path, "removed", rec[key]);
            path.pop();
            if (errors)
              errors.append(error);
            else
              errors = error;
          }
        }
        return errors ?? out ?? v;
      }
      case "string": {
        if (typeof v !== "string")
          return fail(path, "a string", v);
        if (ir.min !== undefined && v.length < ir.min)
          return fail(path, `at least length ${ir.min}`, v.length);
        if (ir.max !== undefined && v.length > ir.max)
          return fail(path, `at most length ${ir.max}`, v.length);
        if (ir.url && !URL.canParse(v))
          return fail(path, "a URL string", v);
        return v;
      }
      case "number": {
        if (typeof v !== "number" || !Number.isFinite(v))
          return fail(path, ir.int ? "an integer" : "a number", v);
        let errors;
        const add = (expected) => {
          const error = fail(path, expected, v);
          if (errors)
            errors.append(error);
          else
            errors = error;
        };
        if (ir.int && !Number.isInteger(v))
          add("an integer");
        if (ir.divisor !== undefined && v % ir.divisor !== 0)
          add(`a number divisible by ${ir.divisor}`);
        if (ir.min !== undefined && (ir.xmin ? v <= ir.min : v < ir.min)) {
          add(ir.min === 0 ? ir.xmin ? "positive" : "non-negative" : `a number ${ir.xmin ? "more than" : "at least"} ${ir.min}`);
        }
        if (ir.max !== undefined && (ir.xmax ? v >= ir.max : v > ir.max)) {
          add(ir.max === 0 ? ir.xmax ? "negative" : "non-positive" : `a number ${ir.xmax ? "less than" : "at most"} ${ir.max}`);
        }
        return errors ?? v;
      }
      case "lit": {
        if (checks(ir, v))
          return v;
        if (typeof ir.v === "object" && ir.v !== null || typeof ir.v === "function") {
          let expected = "the specified reference";
          try {
            const serialized = JSON.stringify(ir.v);
            if (serialized !== undefined) {
              expected = `reference equal to ${serialized}`;
              if (typeof v === "object" && v !== null && JSON.stringify(v) === serialized) {
                expected += " (serialized to the same value)";
              }
            }
          } catch {}
          return fail(path, expected, v);
        }
        return fail(path, expectedOf(ir), v);
      }
      default:
        return checks(ir, v) ? v : fail(path, expectedOf(ir), v);
    }
  }
  function prefixAll(errs, path) {
    for (let i = path.length - 1;i >= 0; i--)
      errs.prefix(path[i]);
    return errs;
  }
  function canRefineUnionFailure(member) {
    const base = unwrapBase(member);
    if (base.k === "array" || base.k === "object")
      return true;
    if (base.k === "string")
      return base.min !== undefined || base.max !== undefined || base.url === true;
    return base.k === "number" && (base.int === true || base.min !== undefined || base.max !== undefined);
  }
  function unionFail(ir, v, path, expected) {
    let best;
    for (const member of ir.members) {
      const base = unwrapBase(member);
      if (!kindMatches(base, v))
        continue;
      if (best !== undefined) {
        best = undefined;
        break;
      }
      best = member;
    }
    if (best === undefined) {
      const discriminated = discriminateFailure(ir.members, v, path);
      if (discriminated !== undefined)
        return discriminated;
    }
    if (best !== undefined) {
      const out = visit(best, v, path);
      if (out instanceof OmpErrors)
        return out;
    }
    if (ir.members.every((member) => unwrapBase(member).k === "object")) {
      const branches = ir.members.flatMap((member) => {
        const result = visit(member, v, path);
        return result instanceof OmpErrors ? [[...result]] : [];
      });
      if (branches.length !== 0) {
        const common = branches[0].filter((entry, index, first) => first.findIndex((candidate) => pathsEqual(candidate.path, entry.path)) === index && branches.every((branch) => branch.some((candidate) => pathsEqual(candidate.path, entry.path))));
        const alternatives = [];
        if (common.length !== 0) {
          for (const entry of common) {
            const expectations = new Set;
            for (const branch of branches) {
              for (const candidate of branch) {
                if (pathsEqual(candidate.path, entry.path)) {
                  expectations.add(candidate.expected.endsWith(" instance") ? "an object" : candidate.expected);
                }
              }
            }
            alternatives.push(new OmpErrors(entry.path, [...expectations].join(" or "), entry.data, { preserveActual: true }));
          }
        } else {
          for (const branch of branches) {
            for (const entry of branch) {
              alternatives.push(new OmpErrors(entry.path, entry.expected.endsWith(" instance") ? "an object" : entry.expected, entry.data, { preserveActual: true }));
            }
          }
        }
        const combined = alternatives[0];
        for (let index = 1;index < alternatives.length; index++)
          combined.append(alternatives[index]);
        return alternatives.length === 1 ? combined : combined.asAlternatives();
      }
    }
    return fail(path, expected ?? expectedOf(ir), v);
  }
  function unwrapBase(member, seen = new Set) {
    if (seen.has(member))
      return member;
    seen.add(member);
    if (member.k === "sub")
      return unwrapBase(member.schema.ir, seen);
    if (member.k === "alias")
      return unwrapBase(member.resolve(), seen);
    if (member.k === "refine")
      return unwrapBase(member.base, seen);
    return member;
  }
  function collectDiscriminants(member, prefix = [], seen = new Set) {
    if (seen.has(member))
      return [];
    seen.add(member);
    if (member.k === "alias")
      return collectDiscriminants(member.resolve(), prefix, seen);
    if (member.k === "sub")
      return collectDiscriminants(member.schema.ir, prefix, seen);
    if (member.k === "refine")
      return collectDiscriminants(member.base, prefix, seen);
    if (member.k !== "object")
      return [];
    const result = [];
    for (const property of member.props) {
      const propertyPath = [...prefix, property.key];
      const value = unwrapBase(property.val);
      if (value.k === "lit")
        result.push({ path: propertyPath, value: value.v });
      else
        result.push(...collectDiscriminants(property.val, propertyPath, new Set(seen)));
    }
    return result;
  }
  function pathsEqual(left, right) {
    return left.length === right.length && left.every((key, index) => key === right[index]);
  }
  function valueAtPath(value, path) {
    let cursor = value;
    for (const key of path) {
      if (typeof cursor !== "object" && typeof cursor !== "function" || cursor === null || !(key in cursor)) {
        return { present: false };
      }
      cursor = cursor[key];
    }
    return { present: true, value: cursor };
  }
  function discriminateFailure(members, value, path) {
    if (typeof value !== "object" || value === null || Array.isArray(value))
      return;
    const byMember = members.map((member) => collectDiscriminants(member));
    const candidates = [];
    for (const discriminants of byMember) {
      for (const discriminant of discriminants) {
        if (candidates.some((candidate) => pathsEqual(candidate.path, discriminant.path)))
          continue;
        const values = [];
        let declared = 0;
        for (const branch of byMember) {
          const match = branch.find((candidate) => pathsEqual(candidate.path, discriminant.path));
          if (match === undefined)
            continue;
          declared++;
          if (!values.some((candidate) => Object.is(candidate, match.value)))
            values.push(match.value);
        }
        if (values.length > 1)
          candidates.push({ path: discriminant.path, distinct: values.length, declared });
      }
    }
    candidates.sort((left, right) => right.distinct - left.distinct || right.declared - left.declared);
    for (const candidate of candidates) {
      const actual = valueAtPath(value, candidate.path);
      const exact = [];
      const defaults = [];
      const expectedMembers = [];
      for (let index = 0;index < members.length; index++) {
        const discriminant = byMember[index].find((item) => pathsEqual(item.path, candidate.path));
        if (discriminant === undefined) {
          defaults.push(members[index]);
          continue;
        }
        expectedMembers.push({ k: "lit", v: discriminant.value });
        if (actual.present && Object.is(actual.value, discriminant.value))
          exact.push(members[index]);
      }
      if (!actual.present) {
        if (defaults.length !== 0 && defaults.length < members.length) {
          return discriminateFailure(defaults, value, path);
        }
        return fail([...path, ...candidate.path], expectedOf({ k: "union", members: expectedMembers }), undefined);
      }
      if (exact.length === 0) {
        if (defaults.length !== 0)
          return discriminateFailure(defaults, value, path);
        return fail([...path, ...candidate.path], expectedOf({ k: "union", members: expectedMembers }), actual.value);
      }
      if (exact.length === 1) {
        const result = visit(exact[0], value, path);
        return result instanceof OmpErrors ? result : undefined;
      }
      const nested = discriminateFailure(exact, value, path);
      if (nested !== undefined)
        return nested;
    }
    return;
  }
  function kindMatches(base, v) {
    switch (base.k) {
      case "array":
        return Array.isArray(v);
      case "object":
      case "anyobject":
        return typeof v === "object" && v !== null && !Array.isArray(v);
      case "string":
        return typeof v === "string";
      case "number":
        return typeof v === "number";
      default:
        return false;
    }
  }

  // ../build/upstream/oh-my-pi/packages/omptype/src/compile.ts
  var own2 = Object.prototype.hasOwnProperty;
  var IDENT = /^[A-Za-z_$][\w$]*$/;
  function litSource(v) {
    if (v === null)
      return "null";
    if (v === undefined)
      return "undefined";
    switch (typeof v) {
      case "string":
      case "boolean":
        return JSON.stringify(v);
      case "number":
        return Number.isFinite(v) ? String(v) : undefined;
      default:
        return;
    }
  }
  function isPrimitiveLiteral(node) {
    return node.k === "lit" && (node.v === null || typeof node.v !== "object" && typeof node.v !== "function");
  }
  function rejectsUndefined(node) {
    switch (node.k) {
      case "unknown":
      case "undefined":
      case "alias":
      case "sub":
        return false;
      case "lit":
        return node.v !== undefined;
      case "union":
        return node.members.every(rejectsUndefined);
      case "intersection":
        return node.members.some(rejectsUndefined);
      case "refine":
        return rejectsUndefined(node.base);
      case "morph":
        return rejectsUndefined(node.input);
      default:
        return true;
    }
  }

  class CompiledMorphContext {
    #path;
    #data;
    constructor(path, data) {
      this.#path = path;
      this.#data = data;
    }
    error(expectation) {
      return new OmpErrors(this.#path, expectation, this.#data);
    }
    reject(expectation) {
      return this.error(expectation);
    }
  }

  class Builder {
    #lines = [];
    #refs = [];
    #activeAliases;
    #id = 0;
    next(prefix) {
      return `${prefix}${this.#id++}`;
    }
    push(line) {
      this.#lines.push(line);
    }
    ref(value) {
      const idx = this.#refs.indexOf(value);
      if (idx >= 0)
        return `R[${idx}]`;
      this.#refs.push(value);
      return `R[${this.#refs.length - 1}]`;
    }
    lit(v) {
      return litSource(v) ?? this.ref(v);
    }
    access(base, key) {
      return typeof key === "string" && IDENT.test(key) ? `${base}.${key}` : `${base}[${this.lit(key)}]`;
    }
    pathExpr(segs) {
      const parts = segs.map((seg) => ("s" in seg) ? this.lit(seg.s) : seg.d);
      return `[${parts.join(",")}]`;
    }
    storedPathExpr(segs) {
      if (segs.length === 0)
        return "undefined";
      if (segs.length === 1) {
        const seg = segs[0];
        return "s" in seg ? this.lit(seg.s) : seg.d;
      }
      const staticParts = [];
      for (const seg of segs) {
        if ("d" in seg)
          return this.pathExpr(segs);
        staticParts.push(seg.s);
      }
      return this.ref(staticParts);
    }
    error(segs, expected, dataExpr) {
      return `new AE(${this.storedPathExpr(segs)},${JSON.stringify(expected)},${dataExpr})`;
    }
    fail(segs, expected, dataExpr) {
      return `return ${this.error(segs, expected, dataExpr)}`;
    }
    appendError(errors, error) {
      return `if(${errors}===undefined)${errors}=${error};else ${errors}.append(${error});`;
    }
    predicate(node, v) {
      switch (node.k) {
        case "unknown":
          return "true";
        case "null":
          return `${v}===null`;
        case "undefined":
          return `${v}===undefined`;
        case "boolean":
          return `typeof ${v}==="boolean"`;
        case "bigint":
          return `typeof ${v}==="bigint"`;
        case "symbol":
          return `typeof ${v}==="symbol"`;
        case "never":
          return "false";
        case "anyobject":
          return `(typeof ${v}==="object"&&${v}!==null)`;
        case "lit":
          return node.v instanceof Date ? `(${v} instanceof Date&&${v}.valueOf()===${node.v.valueOf()})` : `${v}===${this.lit(node.v)}`;
        case "instance":
          return `${v} instanceof ${this.ref(node.ctor)}`;
        case "string": {
          let out = `typeof ${v}==="string"`;
          if (node.min !== undefined)
            out += `&&${v}.length>=${node.min}`;
          if (node.max !== undefined)
            out += `&&${v}.length<=${node.max}`;
          if (node.url)
            out += `&&URL.canParse(${v})`;
          return out;
        }
        case "number": {
          let out = node.int ? `Number.isInteger(${v})` : `Number.isFinite(${v})`;
          if (node.divisor !== undefined)
            out += `&&${v}%${node.divisor}===0`;
          if (node.min !== undefined)
            out += `&&${v}${node.xmin ? ">" : ">="}${node.min}`;
          if (node.max !== undefined)
            out += `&&${v}${node.xmax ? "<" : "<="}${node.max}`;
          return out;
        }
        case "union": {
          const lits = node.members.filter(isPrimitiveLiteral);
          if (lits.length > 8) {
            const values = this.ref(new Set(lits.map((member) => member.v)));
            const literalNodes = new Set(lits);
            const rest = node.members.filter((member) => !literalNodes.has(member));
            let out = `${values}.has(${v})`;
            for (const m of rest)
              out += `||(${this.predicate(m, v)})`;
            return `(${out})`;
          }
          return `(${node.members.map((m) => `(${this.predicate(m, v)})`).join("||")})`;
        }
        case "intersection":
          return `(${node.members.map((member) => `(${this.predicate(member, v)})`).join("&&")})`;
        case "array": {
          const array = this.next("a");
          const index = this.next("i");
          let out = `Array.isArray(${v})`;
          if (node.min !== undefined)
            out += `&&${v}.length>=${node.min}`;
          if (node.max !== undefined)
            out += `&&${v}.length<=${node.max}`;
          const item = `${array}[${index}]`;
          out += `&&((${array})=>{for(let ${index}=0;${index}<${array}.length;${index}++)if(!(${this.predicate(node.el, item)}))return false;return true})(${v})`;
          return out;
        }
        case "object": {
          const checks = [`typeof ${v}==="object"`, `${v}!==null`];
          for (const p of node.props) {
            const av = this.access(v, p.key);
            const present = `${this.lit(p.key)} in ${v}`;
            const predicate = this.predicate(p.val, av);
            checks.push(p.opt || p.hasDefault ? rejectsUndefined(p.val) ? `((${av}!==undefined&&(${predicate}))||!(${present}))` : `(!(${present})||(${predicate}))` : rejectsUndefined(p.val) ? predicate : `((${present})&&(${predicate}))`);
          }
          const stringKey = this.next("k");
          if (node.index !== undefined) {
            checks.push(`(()=>{for(const ${stringKey} in ${v})if(own.call(${v},${stringKey})&&!(${this.predicate(node.index, `${v}[${stringKey}]`)}))return false;return true})()`);
          }
          if (node.patternIndexes !== undefined) {
            for (const pattern of node.patternIndexes) {
              checks.push(`(()=>{for(const ${stringKey} in ${v})if(own.call(${v},${stringKey})&&(${this.predicate(pattern.key, stringKey)})&&!(${this.predicate(pattern.val, `${v}[${stringKey}]`)}))return false;return true})()`);
            }
          }
          if (node.symbolIndex !== undefined) {
            const symbol = this.next("s");
            checks.push(`(()=>{for(const ${symbol} of Object.getOwnPropertySymbols(${v}))if(Object.prototype.propertyIsEnumerable.call(${v},${symbol})&&!(${this.predicate(node.symbolIndex, `${v}[${symbol}]`)}))return false;return true})()`);
          }
          if (node.extras === "reject") {
            const patternMatch = node.patternIndexes?.map((pattern) => `(${this.predicate(pattern.key, stringKey)})`).join("||") ?? "false";
            if (node.index === undefined) {
              checks.push(`(()=>{for(const ${stringKey} in ${v})if(own.call(${v},${stringKey})&&!(${this.declaredCheck(node.props, stringKey)})&&!(${patternMatch}))return false;return true})()`);
            }
            if (node.symbolIndex === undefined) {
              const symbol = this.next("s");
              checks.push(`(()=>{for(const ${symbol} of Object.getOwnPropertySymbols(${v}))if(Object.prototype.propertyIsEnumerable.call(${v},${symbol})&&!(${this.declaredCheck(node.props, symbol)}))return false;return true})()`);
            }
          }
          return `(${checks.join("&&")})`;
        }
        case "sub":
          return `!(${this.ref(node.schema.run)}(${v}) instanceof AE)`;
        default:
          return `!(${this.ref(boundWalk(node))}(${v}) instanceof AE)`;
      }
    }
    declaredCheck(props, keyVar) {
      if (props.length === 0)
        return "false";
      if (props.length > 6) {
        const set = this.ref(new Set(props.map((p) => p.key)));
        return `${set}.has(${keyVar})`;
      }
      return `(${props.map((p) => `${keyVar}===${this.lit(p.key)}`).join("||")})`;
    }
    emitCollectDelegate(node, v, segs, errors, brk, out) {
      const sub = node.k === "sub";
      const runner = sub ? node.schema.run : boundWalk(node);
      const result = this.next("r");
      const args = segs.length > 0 ? `${v},${this.pathExpr(segs)}` : v;
      this.push(`const ${result}=${this.ref(runner)}(${args});`);
      const failure = sub && segs.length > 0 ? `PF(${result},${this.pathExpr(segs)})` : result;
      this.push(`if(${result} instanceof AE){${this.appendError(errors, failure)}${brk === undefined ? "" : `break ${brk};`}}`);
      if (out !== undefined)
        this.push(`${out}=${result};`);
    }
    markErrors(errors) {
      const mark = this.next("n");
      this.push(`const ${mark}=${errors}===void 0?0:${errors}.length;`);
      return mark;
    }
    guardGrowth(errors, mark, brk) {
      this.push(`if((${errors}===void 0?0:${errors}.length)!==${mark})break ${brk};`);
    }
    emitCollectCheck(node, v, segs, errors, failureData = v) {
      if (node.cfg !== undefined || node.k === "refine") {
        this.emitCollectDelegate(node, v, segs, errors);
        return;
      }
      switch (node.k) {
        case "unknown":
          return;
        case "array": {
          this.push(`if(!Array.isArray(${v})){${this.appendError(errors, this.error(segs, "an array", failureData))}}`);
          if (node.min !== undefined) {
            this.push(`else if(${v}.length<${node.min}){${this.appendError(errors, this.error(segs, `at least length ${node.min}`, `${v}.length`))}}`);
          }
          if (node.max !== undefined) {
            this.push(`else if(${v}.length>${node.max}){${this.appendError(errors, this.error(segs, `at most length ${node.max}`, `${v}.length`))}}`);
          }
          this.push("else{");
          const index = this.next("i");
          this.push(`for(let ${index}=0;${index}<${v}.length;${index}++){`);
          this.emitCollectCheck(node.el, `${v}[${index}]`, [...segs, { d: index }], errors);
          this.push("}}");
          return;
        }
        case "tuple": {
          this.push(`if(!Array.isArray(${v})){${this.appendError(errors, this.error(segs, "an array", failureData))}}else{`);
          const requiredPrefix = node.prefix.filter((item) => !item.opt && !item.hasDefault).length;
          const minimum = requiredPrefix + node.postfix.length;
          const maximum = node.prefix.length + node.postfix.length;
          if (minimum > 0) {
            this.push(`if(${v}.length<${minimum}){${this.appendError(errors, this.error(segs, `an array of at least length ${minimum}`, failureData))}}else{`);
          }
          if (node.variadic === undefined) {
            this.push(`if(${v}.length>${maximum}){${this.appendError(errors, this.error(segs, `an array of at most length ${maximum}`, failureData))}}else{`);
          }
          let postfixStart = `${v}.length`;
          if (node.postfix.length > 0) {
            postfixStart = this.next("p");
            this.push(`const ${postfixStart}=${v}.length-${node.postfix.length};`);
          }
          let prefixCount = String(node.prefix.length);
          if (requiredPrefix !== node.prefix.length) {
            prefixCount = this.next("n");
            this.push(`const ${prefixCount}=Math.min(${node.prefix.length},${postfixStart});`);
          }
          for (let index = 0;index < node.prefix.length; index++) {
            if (index >= requiredPrefix)
              this.push(`if(${index}<${prefixCount}){`);
            this.emitCollectCheck(node.prefix[index].val, `${v}[${index}]`, [...segs, { d: String(index) }], errors);
            if (index >= requiredPrefix)
              this.push("}");
          }
          if (node.variadic !== undefined) {
            const index = this.next("i");
            this.push(`for(let ${index}=${prefixCount};${index}<${postfixStart};${index}++){`);
            this.emitCollectCheck(node.variadic, `${v}[${index}]`, [...segs, { d: index }], errors);
            this.push("}");
          }
          for (let index = 0;index < node.postfix.length; index++) {
            const inputIndex = index === 0 ? postfixStart : `${postfixStart}+${index}`;
            this.emitCollectCheck(node.postfix[index], `${v}[${inputIndex}]`, [...segs, { d: inputIndex }], errors);
          }
          if (node.variadic === undefined)
            this.push("}");
          if (minimum > 0)
            this.push("}");
          this.push("}");
          return;
        }
        case "object": {
          if (node.patternIndexes !== undefined || node.symbolIndex !== undefined || node.props.some((prop) => typeof prop.key === "symbol")) {
            this.emitCollectDelegate(node, v, segs, errors);
            return;
          }
          this.push(`if(typeof ${v}!=="object"||${v}===null){${this.appendError(errors, this.error(segs, "an object", failureData))}}else{`);
          for (const prop of node.props) {
            const present = `${this.lit(prop.key)} in ${v}`;
            const propSegs = [...segs, { s: prop.key }];
            if (prop.opt || prop.hasDefault) {
              this.push(`if(${present}){`);
              this.emitCollectCheck(prop.val, this.access(v, prop.key), propSegs, errors);
              this.push("}");
            } else {
              this.push(`if(!(${present})){${this.appendError(errors, this.error(propSegs, expectedOf(prop.val), "M"))}}else{`);
              this.emitCollectCheck(prop.val, this.access(v, prop.key), propSegs, errors);
              this.push("}");
            }
          }
          if (node.index !== undefined) {
            const key = this.next("k");
            this.push(`for(const ${key} in ${v})if(own.call(${v},${key})){`);
            this.emitCollectCheck(node.index, `${v}[${key}]`, [...segs, { d: key }], errors);
            this.push("}");
          } else if (node.extras === "reject") {
            const key = this.next("k");
            this.push(`for(const ${key} in ${v})if(own.call(${v},${key})&&!(${this.declaredCheck(node.props, key)})){`);
            this.push(this.appendError(errors, this.error([...segs, { d: key }], "removed", `${v}[${key}]`)));
            this.push("}");
          }
          if (node.extras === "reject") {
            const symbol = this.next("s");
            this.push(`for(const ${symbol} of Object.getOwnPropertySymbols(${v}))if(Object.prototype.propertyIsEnumerable.call(${v},${symbol})&&!(${this.declaredCheck(node.props, symbol)})){${this.appendError(errors, this.error([...segs, { d: symbol }], "removed", `${v}[${symbol}]`))}}`);
          }
          this.push("}");
          return;
        }
        case "union": {
          const failure = node.members.some(canRefineUnionFailure) ? `UF(${this.ref(node)},${failureData},${this.pathExpr(segs)},${JSON.stringify(expectedOf(node))})` : this.error(segs, expectedOf(node), failureData);
          this.push(`if(!(${this.predicate(node, v)})){${this.appendError(errors, failure)}}`);
          return;
        }
        case "string": {
          this.push(`if(typeof ${v}!=="string"){${this.appendError(errors, this.error(segs, "a string", failureData))}}`);
          if (node.min !== undefined) {
            this.push(`else if(${v}.length<${node.min}){${this.appendError(errors, this.error(segs, `at least length ${node.min}`, `${v}.length`))}}`);
          }
          if (node.max !== undefined) {
            this.push(`else if(${v}.length>${node.max}){${this.appendError(errors, this.error(segs, `at most length ${node.max}`, `${v}.length`))}}`);
          }
          if (node.url) {
            this.push(`else if(!URL.canParse(${v})){${this.appendError(errors, this.error(segs, "a URL string", failureData))}}`);
          }
          return;
        }
        case "number": {
          this.push(`if(typeof ${v}!=="number"||!Number.isFinite(${v})){${this.appendError(errors, this.error(segs, node.int ? "an integer" : "a number", failureData))}}else{`);
          if (node.int) {
            this.push(`if(!Number.isInteger(${v})){${this.appendError(errors, this.error(segs, "an integer", failureData))}}`);
          }
          if (node.divisor !== undefined) {
            this.push(`if(${v}%${node.divisor}!==0){${this.appendError(errors, this.error(segs, `a number divisible by ${node.divisor}`, failureData))}}`);
          }
          if (node.min !== undefined) {
            const expected = node.min === 0 ? node.xmin ? "positive" : "non-negative" : `a number ${node.xmin ? "more than" : "at least"} ${node.min}`;
            this.push(`if(${v}${node.xmin ? "<=" : "<"}${node.min}){${this.appendError(errors, this.error(segs, expected, failureData))}}`);
          }
          if (node.max !== undefined) {
            const expected = node.max === 0 ? node.xmax ? "negative" : "non-positive" : `a number ${node.xmax ? "less than" : "at most"} ${node.max}`;
            this.push(`if(${v}${node.xmax ? ">=" : ">"}${node.max}){${this.appendError(errors, this.error(segs, expected, failureData))}}`);
          }
          this.push("}");
          return;
        }
        case "lit":
          if (node.v !== null && typeof node.v === "object" && !(node.v instanceof Date) || typeof node.v === "function") {
            this.emitCollectDelegate(node, v, segs, errors);
          } else {
            this.push(`if(!(${this.predicate(node, v)})){${this.appendError(errors, this.error(segs, expectedOf(node), failureData))}}`);
          }
          return;
        case "intersection":
        case "sub":
          this.emitCollectDelegate(node, v, segs, errors);
          return;
        case "null":
        case "undefined":
        case "boolean":
        case "bigint":
        case "symbol":
        case "never":
        case "anyobject":
        case "instance":
          this.push(`if(!(${this.predicate(node, v)})){${this.appendError(errors, this.error(segs, expectedOf(node), failureData))}}`);
          return;
        default:
          this.emitCollectDelegate(node, v, segs, errors);
      }
    }
    emitTupleShape(node, v, segs, errors, brk, failureData) {
      this.push(`if(!Array.isArray(${v})){${this.appendError(errors, this.error(segs, "an array", failureData))}break ${brk};}`);
      const requiredPrefix = node.prefix.filter((item) => !item.opt && !item.hasDefault).length;
      const minimum = requiredPrefix + node.postfix.length;
      if (minimum > 0) {
        this.push(`if(${v}.length<${minimum}){${this.appendError(errors, this.error(segs, `an array of at least length ${minimum}`, failureData))}break ${brk};}`);
      }
      if (node.variadic === undefined) {
        const maximum = node.prefix.length + node.postfix.length;
        this.push(`if(${v}.length>${maximum}){${this.appendError(errors, this.error(segs, `an array of at most length ${maximum}`, failureData))}break ${brk};}`);
      }
      let postfixStart = `${v}.length`;
      if (node.postfix.length > 0) {
        postfixStart = this.next("p");
        this.push(`const ${postfixStart}=${v}.length-${node.postfix.length};`);
      }
      let prefixCount = String(node.prefix.length);
      if (requiredPrefix !== node.prefix.length) {
        prefixCount = this.next("n");
        this.push(`const ${prefixCount}=Math.min(${node.prefix.length},${postfixStart});`);
      }
      return { postfixStart, prefixCount, requiredPrefix };
    }
    emitDefaultFill(val, def, isFactory, target, segs, errors) {
      if (isFactory && typeof def === "function") {
        const candidate = this.next("d");
        const resolved = this.next("t");
        const label = this.next("L");
        this.push(`const ${candidate}=${this.ref(def)}();let ${resolved};${label}:{`);
        this.emitCollectProduce(val, candidate, segs, resolved, errors, label);
        this.push(`${target}=${resolved};}`);
      } else {
        this.push(`${target}=${litSource(def) ?? `MD(${this.ref(def)})`};`);
      }
    }
    emitCollectProduce(node, v, segs, out, errors, brk, failureData = v) {
      if (node.cfg !== undefined || node.k === "refine") {
        this.emitCollectDelegate(node, v, segs, errors, brk, out);
        return;
      }
      if (!hasMorph(node)) {
        this.emitCollectCheck(node, v, segs, errors, failureData);
        this.push(`${out}=${v};`);
        return;
      }
      switch (node.k) {
        case "sub":
          this.emitCollectDelegate(node, v, segs, errors, brk, out);
          return;
        case "morph": {
          const input = this.next("t");
          this.push(`let ${input};`);
          const mark = this.markErrors(errors);
          this.emitCollectProduce(node.input, v, segs, input, errors, brk, failureData);
          this.guardGrowth(errors, mark, brk);
          const context = this.next("c");
          const result = this.next("r");
          this.push(`const ${context}=new MC(${this.storedPathExpr(segs)},${input});`);
          this.push(`const ${result}=${this.ref(node.fn)}(${input},${context});`);
          this.push(`if(${result} instanceof AE){${this.appendError(errors, result)}break ${brk};}`);
          if (node.out === undefined)
            this.push(`${out}=${result};`);
          else
            this.emitCollectProduce(node.out, result, segs, out, errors, brk);
          return;
        }
        case "alias": {
          let active = this.#activeAliases;
          if (active === undefined) {
            active = new Set;
            this.#activeAliases = active;
          }
          if (active.has(node)) {
            this.emitCollectDelegate(node, v, segs, errors, brk, out);
            return;
          }
          active.add(node);
          try {
            this.emitCollectProduce(node.resolve(), v, segs, out, errors, brk, failureData);
          } finally {
            active.delete(node);
          }
          return;
        }
        case "union": {
          const ok = this.next("u");
          this.push(`let ${ok}=false;`);
          const label = this.next("b");
          this.push(`${label}:{`);
          for (const m of node.members) {
            if (m.k !== "sub" && !hasMorph(m)) {
              this.push(`if(${this.predicate(m, v)}){${out}=${v};${ok}=true;break ${label};}`);
            }
          }
          for (const m of node.members) {
            if (m.k === "sub" || hasMorph(m)) {
              const runner = m.k === "sub" ? m.schema.run : m.k === "alias" ? boundWalk(m) : compile(m);
              const r = this.next("r");
              this.push(`const ${r}=${this.ref(runner)}(${v});`);
              this.push(`if(!(${r} instanceof AE)){${out}=${r};${ok}=true;break ${label};}`);
            }
          }
          this.push("}");
          const failure = `UF(${this.ref(node)},${failureData},${this.pathExpr(segs)},${JSON.stringify(expectedOf(node))})`;
          this.push(`if(!${ok}){${this.appendError(errors, failure)}break ${brk};}`);
          return;
        }
        case "array": {
          this.push(`if(!Array.isArray(${v})){${this.appendError(errors, this.error(segs, "an array", failureData))}break ${brk};}`);
          if (node.min !== undefined) {
            this.push(`if(${v}.length<${node.min}){${this.appendError(errors, this.error(segs, `at least length ${node.min}`, `${v}.length`))}break ${brk};}`);
          }
          if (node.max !== undefined) {
            this.push(`if(${v}.length>${node.max}){${this.appendError(errors, this.error(segs, `at most length ${node.max}`, `${v}.length`))}break ${brk};}`);
          }
          const array = this.next("a");
          const index = this.next("i");
          const input = this.next("x");
          const element = this.next("t");
          const label = this.next("L");
          this.push(`const ${array}=new Array(${v}.length);`);
          this.push(`for(let ${index}=0;${index}<${v}.length;${index}++){const ${input}=${v}[${index}];let ${element};${label}:{`);
          this.emitCollectProduce(node.el, input, [...segs, { d: index }], element, errors, label);
          this.push(`${array}[${index}]=${element};}}`);
          this.push(`${out}=${array};`);
          return;
        }
        case "tuple": {
          const { postfixStart, prefixCount, requiredPrefix } = this.emitTupleShape(node, v, segs, errors, brk, failureData);
          const tuple = this.next("a");
          this.push(`const ${tuple}=[...${v}];`);
          for (let index = 0;index < node.prefix.length; index++) {
            const item = node.prefix[index];
            const itemSegs = [...segs, { s: index }];
            const input = `${v}[${index}]`;
            const output = `${tuple}[${index}]`;
            const label = this.next("L");
            if (index >= requiredPrefix)
              this.push(`if(${index}<${prefixCount}){`);
            this.push(`${label}:{`);
            if (hasMorph(item.val)) {
              const temporary = this.next("t");
              this.push(`let ${temporary};`);
              this.emitCollectProduce(item.val, input, itemSegs, temporary, errors, label);
              this.push(`${output}=${temporary};`);
            } else {
              this.emitCollectCheck(item.val, input, itemSegs, errors);
            }
            this.push("}");
            if (index >= requiredPrefix) {
              if (item.hasDefault) {
                this.push("}else{");
                this.emitDefaultFill(item.val, item.def, item.defFactory === true, output, itemSegs, errors);
                this.push("}");
              } else {
                this.push("}");
              }
            }
          }
          if (node.variadic !== undefined) {
            const index = this.next("i");
            const input = this.next("x");
            const label = this.next("L");
            this.push(`for(let ${index}=${prefixCount};${index}<${postfixStart};${index}++){const ${input}=${v}[${index}];${label}:{`);
            if (hasMorph(node.variadic)) {
              const temporary = this.next("t");
              this.push(`let ${temporary};`);
              this.emitCollectProduce(node.variadic, input, [...segs, { d: index }], temporary, errors, label);
              this.push(`${tuple}[${index}]=${temporary};`);
            } else {
              this.emitCollectCheck(node.variadic, input, [...segs, { d: index }], errors);
            }
            this.push("}}");
          }
          for (let index = 0;index < node.postfix.length; index++) {
            const inputIndex = index === 0 ? postfixStart : `${postfixStart}+${index}`;
            const input = `${v}[${inputIndex}]`;
            const item = node.postfix[index];
            const label = this.next("L");
            this.push(`${label}:{`);
            if (hasMorph(item)) {
              const temporary = this.next("t");
              this.push(`let ${temporary};`);
              this.emitCollectProduce(item, input, [...segs, { d: inputIndex }], temporary, errors, label);
              this.push(`${tuple}[${inputIndex}]=${temporary};`);
            } else {
              this.emitCollectCheck(item, input, [...segs, { d: inputIndex }], errors);
            }
            this.push("}");
          }
          this.push(`${out}=${tuple};`);
          return;
        }
        case "object": {
          if (node.patternIndexes !== undefined || node.symbolIndex !== undefined || node.props.some((prop) => typeof prop.key === "symbol")) {
            this.emitCollectDelegate(node, v, segs, errors, brk, out);
            return;
          }
          this.push(`if(typeof ${v}!=="object"||${v}===null){${this.appendError(errors, this.error(segs, "an object", failureData))}break ${brk};}`);
          const object = this.next("o");
          const fresh = node.extras === "delete" && node.index === undefined;
          this.push(fresh ? `const ${object}={};` : `const ${object}={...${v}};`);
          for (const prop of node.props) {
            const present = `${this.lit(prop.key)} in ${v}`;
            const propSegs = [...segs, { s: prop.key }];
            const input = this.access(v, prop.key);
            const output = this.access(object, prop.key);
            const label = this.next("L");
            this.push(`if(!(${present})){`);
            if (prop.hasDefault) {
              this.emitDefaultFill(prop.val, prop.def, prop.defFactory === true, output, propSegs, errors);
            } else if (!prop.opt) {
              this.push(this.appendError(errors, this.error(propSegs, expectedOf(prop.val), "M")));
            }
            this.push(`}else{${label}:{`);
            if (hasMorph(prop.val)) {
              const temporary = this.next("t");
              this.push(`let ${temporary};`);
              this.emitCollectProduce(prop.val, input, propSegs, temporary, errors, label);
              this.push(`${output}=${temporary};`);
            } else {
              this.emitCollectCheck(prop.val, input, propSegs, errors);
              if (fresh)
                this.push(`${output}=${input};`);
            }
            this.push("}}");
          }
          if (node.index !== undefined) {
            const key = this.next("k");
            const label = this.next("L");
            this.push(`for(const ${key} in ${v})if(own.call(${v},${key})){${label}:{`);
            if (hasMorph(node.index)) {
              const temporary = this.next("t");
              this.push(`let ${temporary};`);
              this.emitCollectProduce(node.index, `${v}[${key}]`, [...segs, { d: key }], temporary, errors, label);
              this.push(`${object}[${key}]=${temporary};`);
            } else {
              this.emitCollectCheck(node.index, `${v}[${key}]`, [...segs, { d: key }], errors);
            }
            this.push("}}");
          } else if (node.extras === "reject") {
            const key = this.next("k");
            this.push(`for(const ${key} in ${v})if(own.call(${v},${key})&&!(${this.declaredCheck(node.props, key)})){${this.appendError(errors, this.error([...segs, { d: key }], "removed", `${v}[${key}]`))}}`);
          }
          if (node.extras === "reject") {
            const symbol = this.next("s");
            this.push(`for(const ${symbol} of Object.getOwnPropertySymbols(${v}))if(Object.prototype.propertyIsEnumerable.call(${v},${symbol})&&!(${this.declaredCheck(node.props, symbol)})){${this.appendError(errors, this.error([...segs, { d: symbol }], "removed", `${v}[${symbol}]`))}}`);
          }
          this.push(`${out}=${object};`);
          return;
        }
        case "intersection": {
          const current = this.next("t");
          this.push(`let ${current}=${v};`);
          const mark = this.markErrors(errors);
          for (let index = 0;index < node.members.length; index++) {
            if (index > 0)
              this.guardGrowth(errors, mark, brk);
            const member = node.members[index];
            if (hasMorph(member))
              this.emitCollectProduce(member, current, segs, current, errors, brk);
            else
              this.emitCollectCheck(member, current, segs, errors);
          }
          this.push(`${out}=${current};`);
          return;
        }
        default:
          this.emitCollectDelegate(node, v, segs, errors, brk, out);
      }
    }
    build(ir) {
      const errors = this.next("e");
      let ret;
      if (hasMorph(ir)) {
        const label = this.next("L");
        this.push(`let ${errors};let o;${label}:{`);
        this.emitCollectProduce(ir, "v", [], "o", errors, label);
        this.push("}");
        ret = "o";
      } else {
        this.push(`let ${errors};`);
        this.emitCollectCheck(ir, "v", [], errors);
        ret = "v";
      }
      this.push(`if(${errors}!==undefined)return ${errors};`);
      const src = `return function(v){${this.#lines.join("")}return ${ret}}`;
      const make = new Function("R", "AE", "M", "PF", "UF", "MC", "own", "MD", src);
      return make(this.#refs, OmpErrors, MISSING, prefixErrors, unionFail, CompiledMorphContext, own2, materializeDefault);
    }
    emitAllows(node, v) {
      switch (node.k) {
        case "array": {
          const array = this.next("a");
          const index = this.next("i");
          this.push(`const ${array}=${v};if(!Array.isArray(${array}))return false;`);
          if (node.min !== undefined)
            this.push(`if(${array}.length<${node.min})return false;`);
          if (node.max !== undefined)
            this.push(`if(${array}.length>${node.max})return false;`);
          this.push(`for(let ${index}=0;${index}<${array}.length;${index}++){`);
          this.emitAllows(node.el, `${array}[${index}]`);
          this.push("}");
          return;
        }
        case "object": {
          const object = this.next("o");
          this.push(`const ${object}=${v};if(typeof ${object}!=="object"||${object}===null)return false;`);
          for (const prop of node.props) {
            const value = this.next("p");
            const present = `${this.lit(prop.key)} in ${object}`;
            this.push(`const ${value}=${this.access(object, prop.key)};`);
            if (prop.opt || prop.hasDefault) {
              if (rejectsUndefined(prop.val)) {
                this.push(`if(${value}!==undefined){`);
                this.emitAllows(prop.val, value);
                this.push(`}else if(${present})return false;`);
              } else {
                this.push(`if(${present}){`);
                this.emitAllows(prop.val, value);
                this.push("}");
              }
            } else {
              if (!rejectsUndefined(prop.val))
                this.push(`if(!(${present}))return false;`);
              this.emitAllows(prop.val, value);
            }
          }
          const stringKey = this.next("k");
          if (node.index !== undefined) {
            this.push(`for(const ${stringKey} in ${object}){if(!own.call(${object},${stringKey}))continue;`);
            this.emitAllows(node.index, `${object}[${stringKey}]`);
            this.push("}");
          }
          if (node.patternIndexes !== undefined) {
            for (const pattern of node.patternIndexes) {
              this.push(`for(const ${stringKey} in ${object})if(own.call(${object},${stringKey})&&(${this.predicate(pattern.key, stringKey)})&&!(${this.predicate(pattern.val, `${object}[${stringKey}]`)}))return false;`);
            }
          }
          if (node.symbolIndex !== undefined) {
            const symbol = this.next("s");
            this.push(`for(const ${symbol} of Object.getOwnPropertySymbols(${object})){if(!Object.prototype.propertyIsEnumerable.call(${object},${symbol}))continue;`);
            this.emitAllows(node.symbolIndex, `${object}[${symbol}]`);
            this.push("}");
          }
          if (node.extras === "reject") {
            const patternMatch = node.patternIndexes?.map((pattern) => `(${this.predicate(pattern.key, stringKey)})`).join("||") ?? "false";
            if (node.index === undefined) {
              this.push(`for(const ${stringKey} in ${object})if(own.call(${object},${stringKey})&&!(${this.declaredCheck(node.props, stringKey)})&&!(${patternMatch}))return false;`);
            }
            if (node.symbolIndex === undefined) {
              const symbol = this.next("s");
              this.push(`for(const ${symbol} of Object.getOwnPropertySymbols(${object}))if(Object.prototype.propertyIsEnumerable.call(${object},${symbol})&&!(${this.declaredCheck(node.props, symbol)}))return false;`);
            }
          }
          return;
        }
        case "union": {
          const sources = [];
          for (const member of node.members) {
            if (!isPrimitiveLiteral(member))
              break;
            const source = litSource(member.v);
            if (source === undefined)
              break;
            sources.push(source);
          }
          if (sources.length === node.members.length && sources.length >= 4) {
            this.push(`switch(${v}){${sources.map((source) => `case ${source}:`).join("")}break;default:return false;}`);
            return;
          }
          this.push(`if(!(${this.predicate(node, v)}))return false;`);
          return;
        }
        default:
          this.push(`if(!(${this.predicate(node, v)}))return false;`);
      }
    }
    buildAllows(ir) {
      this.emitAllows(ir, "v");
      const src = `return function(v){${this.#lines.join("")}return true}`;
      const make = new Function("R", "AE", "own", src);
      return make(this.#refs, OmpErrors, own2);
    }
  }
  function prefixErrors(errs, parts) {
    for (let i = parts.length - 1;i >= 0; i--)
      errs.prefix(parts[i]);
    return errs;
  }
  var kWalk = Symbol("omptype.boundWalk");
  function boundWalk(node) {
    const tagged = node;
    let fn = tagged[kWalk];
    if (!fn) {
      fn = (value, path) => walk(node, value, path);
      tagged[kWalk] = fn;
    }
    return fn;
  }
  function resolvedRoot(ir) {
    return ir.k === "alias" ? ir.resolve() : ir;
  }
  var compiledCache = new WeakMap;
  var allowsCache = new WeakMap;
  function compile(ir) {
    const root = resolvedRoot(ir);
    const validator = compiledCache.get(root);
    if (validator === undefined) {
      const built = {};
      compiledCache.set(root, (value) => built.value === undefined ? walk(root, value) : built.value(value));
      const compiled = new Builder().build(root);
      built.value = compiled;
      compiledCache.set(root, compiled);
      return compiled;
    }
    return validator;
  }
  function compileAllows(ir) {
    const root = resolvedRoot(ir);
    const validator = allowsCache.get(root);
    if (validator === undefined) {
      const built = {};
      allowsCache.set(root, (value) => built.value === undefined ? !(walk(root, value) instanceof OmpErrors) : built.value(value));
      const compiled = new Builder().buildAllows(root);
      built.value = compiled;
      allowsCache.set(root, compiled);
      return compiled;
    }
    return validator;
  }

  // ../build/upstream/oh-my-pi/packages/omptype/src/json-schema.ts
  function irToJsonSchema(ir, options) {
    const ctx = { options, defs: new Map, refs: new Map };
    let schema = emit(ir, ctx);
    if (ctx.defs.size > 0)
      schema.$defs = Object.fromEntries(ctx.defs);
    if (options?.target === "draft-07")
      schema = toDraft7(schema);
    const dialect = options?.dialect === null ? undefined : options?.dialect ?? dialectFor(options?.target);
    if (dialect !== undefined)
      schema.$schema = dialect;
    if (options?.description !== undefined)
      schema.description = options.description;
    return schema;
  }
  function dialectFor(target) {
    if (target === "draft-2020-12")
      return "https://json-schema.org/draft/2020-12/schema";
    if (target === "draft-07")
      return "http://json-schema.org/draft-07/schema#";
    return target !== undefined && (target.startsWith("http://") || target.startsWith("https://")) ? target : undefined;
  }
  function fallback(schema, ctx) {
    const replacement = ctx.options?.fallback?.({ base: schema });
    if (replacement === true)
      return {};
    if (replacement === false)
      return { not: {} };
    return typeof replacement === "object" && replacement !== null ? replacement : schema;
  }
  function toDraft7(schema) {
    const converted = {};
    for (const key in schema) {
      const value = schema[key];
      if (key === "$ref" && typeof value === "string") {
        converted.$ref = value.replace("#/$defs/", "#/definitions/");
      } else if (key === "$defs") {
        converted.definitions = toDraft7(value);
      } else if (key === "prefixItems" && Array.isArray(value)) {
        converted.items = value.map((item) => typeof item === "object" && item !== null ? toDraft7(item) : item);
      } else if (key === "items" && "prefixItems" in schema) {
        converted.additionalItems = typeof value === "object" && value !== null ? toDraft7(value) : value;
      } else if (Array.isArray(value)) {
        converted[key] = value.map((item) => typeof item === "object" && item !== null ? toDraft7(item) : item);
      } else if (typeof value === "object" && value !== null) {
        converted[key] = toDraft7(value);
      } else {
        converted[key] = value;
      }
    }
    return converted;
  }
  function emit(ir, ctx) {
    let schema;
    switch (ir.k) {
      case "unknown":
        schema = {};
        break;
      case "undefined":
        schema = fallback({}, ctx);
        break;
      case "null":
        schema = { type: "null" };
        break;
      case "boolean":
        schema = { type: "boolean" };
        break;
      case "bigint":
        schema = { type: "integer" };
        break;
      case "symbol":
        schema = fallback({}, ctx);
        break;
      case "never":
        schema = { not: {} };
        break;
      case "anyobject":
        schema = { type: "object" };
        break;
      case "string":
        schema = emitString(ir);
        break;
      case "number":
        schema = emitNumber(ir);
        break;
      case "lit":
        schema = emitLiteral(ir.v);
        break;
      case "union":
        schema = emitUnion(ir.members, ctx);
        break;
      case "intersection":
        schema = { allOf: ir.members.map((member) => emit(member, ctx)) };
        break;
      case "array":
        schema = { type: "array", items: emit(ir.el, ctx) };
        if (ir.min !== undefined)
          schema.minItems = ir.min;
        if (ir.max !== undefined)
          schema.maxItems = ir.max;
        break;
      case "tuple": {
        const prefixItems = ir.prefix.map((item) => {
          const itemSchema = emit(item.val, ctx);
          if (item.hasDefault) {
            itemSchema.default = item.defFactory && typeof item.def === "function" ? item.def() : item.def;
          }
          return itemSchema;
        });
        const required = ir.prefix.reduce((count, item) => count + (item.opt || item.hasDefault ? 0 : 1), ir.postfix.length);
        schema = { type: "array", prefixItems, minItems: required };
        if (ir.variadic === undefined) {
          schema.items = false;
        } else {
          schema.items = emit(ir.variadic, ctx);
        }
        break;
      }
      case "object":
        schema = emitObject(ir.props, ir.index, ir.extras, ctx);
        break;
      case "instance":
        schema = ir.ctor === Date ? { type: "string", format: "date-time" } : fallback({ type: "object" }, ctx);
        break;
      case "refine":
        schema = emit(ir.base, ctx);
        if (ir.json !== undefined)
          Object.assign(schema, ir.json);
        break;
      case "morph":
        schema = ctx.options?.io === "input" ? emit(ir.input, ctx) : fallback(emit(ir.out ?? ir.input, ctx), ctx);
        break;
      case "alias": {
        const known = ctx.refs.get(ir.resolve);
        if (known !== undefined) {
          schema = { $ref: `#/$defs/${known}` };
          break;
        }
        let name = ir.name.replace(/[^\w.-]/g, "_");
        while ([...ctx.refs.values()].includes(name))
          name = `${name}_`;
        ctx.refs.set(ir.resolve, name);
        ctx.defs.set(name, emit(ir.resolve(), ctx));
        schema = { $ref: `#/$defs/${name}` };
        break;
      }
      case "sub":
        if (ctx.options?.io === "output" && ir.schema.opaqueOutput) {
          schema = {};
        } else if (ctx.options?.io === "output" && ir.schema.stepOut !== undefined) {
          schema = emit(ir.schema.stepOut, ctx);
        } else if (ctx.options?.io === "input") {
          schema = emit(ir.schema.ir, ctx);
        } else {
          schema = ir.schema.hasSteps ? fallback(emit(ir.schema.ir, ctx), ctx) : emit(ir.schema.ir, ctx);
        }
        if (ir.schema.ir.desc !== undefined)
          schema.description = ir.schema.ir.desc;
        else if (ir.schema.description !== undefined && ir.descAuto !== true) {
          schema.description = ir.schema.description;
        }
        break;
    }
    if (ir.desc !== undefined && ir.descAuto !== true)
      schema.description = ir.desc;
    return schema;
  }
  function emitString(ir) {
    const schema = { type: "string" };
    if (ir.min !== undefined)
      schema.minLength = ir.min;
    if (ir.max !== undefined)
      schema.maxLength = ir.max;
    if (ir.url)
      schema.format = "uri";
    return schema;
  }
  function emitNumber(ir) {
    const schema = { type: ir.int ? "integer" : "number" };
    if (ir.min !== undefined)
      schema[ir.xmin ? "exclusiveMinimum" : "minimum"] = ir.min;
    if (ir.max !== undefined)
      schema[ir.xmax ? "exclusiveMaximum" : "maximum"] = ir.max;
    if (ir.divisor !== undefined)
      schema.multipleOf = ir.divisor;
    return schema;
  }
  function emitLiteral(value) {
    if (value instanceof Date)
      return { type: "string", format: "date-time", const: value.toISOString() };
    if (isJsonValue(value))
      return { const: value };
    switch (typeof value) {
      case "string":
        return { type: "string" };
      case "number":
        return { type: "number" };
      case "boolean":
        return { type: "boolean" };
      case "bigint":
        return { type: "integer" };
      case "object":
        return { type: "object" };
      default:
        return {};
    }
  }
  function emitUnion(members, ctx) {
    const defined = members.filter((member) => member.k !== "undefined");
    if (defined.length === 0)
      return {};
    if (defined.length === 1)
      return emit(defined[0], ctx);
    if (defined.every((member) => member.k === "lit" && isJsonValue(member.v))) {
      const values = defined.map((member) => member.v);
      const schema = { enum: values };
      const scalarType = homogeneousScalarType(values);
      if (scalarType !== undefined)
        schema.type = scalarType;
      return schema;
    }
    return { anyOf: defined.map((member) => emit(member, ctx)) };
  }
  function homogeneousScalarType(values) {
    const first = jsonScalarType(values[0]);
    if (first === undefined)
      return;
    for (let i = 1;i < values.length; i++) {
      if (jsonScalarType(values[i]) !== first)
        return;
    }
    return first;
  }
  function jsonScalarType(value) {
    if (value === null)
      return "null";
    switch (typeof value) {
      case "string":
      case "number":
      case "boolean":
        return typeof value;
      default:
        return;
    }
  }
  function emitObject(props, index, extras, ctx) {
    const properties = {};
    const required = [];
    const filled = (prop) => !prop.opt && (ctx.options?.io === "output" || !prop.hasDefault);
    const ordered = [...props.filter(filled), ...props.filter((prop) => !filled(prop))];
    for (const prop of ordered) {
      if (typeof prop.key === "symbol")
        throw new TypeError("Cannot convert a symbol to a string");
      const key = String(prop.key);
      const propertySchema = emit(prop.val, ctx);
      if (prop.hasDefault) {
        propertySchema.default = prop.defFactory ? prop.def() : prop.def;
      }
      properties[key] = propertySchema;
      if (filled(prop))
        required.push(key);
    }
    const schema = { type: "object", properties };
    if (required.length > 0)
      schema.required = required;
    if (index !== undefined)
      schema.additionalProperties = emit(index, ctx);
    else if (extras === "reject")
      schema.additionalProperties = false;
    return schema;
  }
  function isJsonValue(value, seen = new Set) {
    if (value === null || typeof value === "string" || typeof value === "boolean")
      return true;
    if (typeof value === "number")
      return Number.isFinite(value);
    if (typeof value !== "object" || seen.has(value))
      return false;
    seen.add(value);
    if (Array.isArray(value)) {
      for (const item of value) {
        if (!isJsonValue(item, seen))
          return false;
      }
      seen.delete(value);
      return true;
    }
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null)
      return false;
    for (const key in value) {
      if (Object.hasOwn(value, key) && !isJsonValue(value[key], seen))
        return false;
    }
    seen.delete(value);
    return true;
  }

  // ../build/upstream/oh-my-pi/packages/omptype/src/type.ts
  useAssignability(isSubtype);
  var Type = Object.defineProperty(function Type() {}, Symbol.hasInstance, {
    value: (value) => (typeof value === "function" || typeof value === "object" && value !== null) && (IR_BRAND in value)
  });
  function descriptionOf(ir, seen = new Set) {
    if (ir.desc !== undefined)
      return ir.desc;
    if (seen.has(ir))
      return ir.k === "alias" ? ir.name : expectedOf(ir);
    seen.add(ir);
    if (ir.k === "alias")
      return descriptionOf(ir.resolve(), seen);
    if (ir.k === "object") {
      return `{ ${ir.props.map((prop) => `${String(prop.key)}${prop.opt ? "?" : ""}: ${descriptionOf(prop.val, seen)}`).join(", ")} }`;
    }
    return expectedOf(ir);
  }
  function errorConfigOf(config) {
    return {
      ...config.description === undefined || config.expected !== undefined ? {} : { expected: config.description },
      ...config.expected === undefined ? {} : { expected: config.expected },
      ...config.actual === undefined ? {} : { actual: config.actual },
      ...config.problem === undefined ? {} : { problem: config.problem },
      ...config.message === undefined ? {} : { message: config.message }
    };
  }
  function configureNode(ir, config) {
    return {
      ...ir,
      cfg: { ...ir.cfg, ...errorConfigOf(config) },
      ...config.description === undefined ? {} : { desc: config.description }
    };
  }
  function configureSelected(ir, config, selector) {
    const domain = ir.k === "string" || ir.k === "number" || ir.k === "boolean" || ir.k === "bigint" || ir.k === "symbol" ? ir.k : ir.k === "object" || ir.k === "array" || ir.k === "tuple" || ir.k === "instance" || ir.k === "anyobject" ? "object" : undefined;
    const kind = ir.k === "number" && ir.divisor !== undefined ? "divisor" : "domain";
    if ((selector.kind === undefined || selector.kind === kind) && (selector.where === undefined || selector.where({ kind, domain }))) {
      return configureNode(ir, config);
    }
    switch (ir.k) {
      case "array":
        return { ...ir, el: configureSelected(ir.el, config, selector) };
      case "tuple":
        return {
          ...ir,
          prefix: ir.prefix.map((item) => ({ ...item, val: configureSelected(item.val, config, selector) })),
          ...ir.variadic === undefined ? {} : { variadic: configureSelected(ir.variadic, config, selector) },
          postfix: ir.postfix.map((item) => configureSelected(item, config, selector))
        };
      case "object":
        return {
          ...ir,
          props: ir.props.map((prop) => ({ ...prop, val: configureSelected(prop.val, config, selector) })),
          ...ir.index === undefined ? {} : { index: configureSelected(ir.index, config, selector) },
          symbolIndex: ir.symbolIndex === undefined ? undefined : configureSelected(ir.symbolIndex, config, selector),
          patternIndexes: ir.patternIndexes?.map((index) => ({
            key: configureSelected(index.key, config, selector),
            val: configureSelected(index.val, config, selector)
          }))
        };
      case "union":
      case "intersection":
        return { ...ir, members: ir.members.map((member) => configureSelected(member, config, selector)) };
      case "refine":
        return { ...ir, base: configureSelected(ir.base, config, selector) };
      case "morph":
        return {
          ...ir,
          input: configureSelected(ir.input, config, selector),
          ...ir.out === undefined ? {} : { out: configureSelected(ir.out, config, selector) }
        };
      default:
        return ir;
    }
  }

  class Ctx {
    expectation;
    errors;
    path;
    #data;
    constructor(data, path = []) {
      this.#data = data;
      this.path = path.map((key) => typeof key === "symbol" ? String(key) : key);
    }
    error(input) {
      const detail = typeof input === "string" ? { expected: input } : input;
      const error = OmpErrors.single([...detail.path ?? detail.relativePath ?? []], detail.expected, this.#data, {
        preserveActual: true,
        ...Object.hasOwn(detail, "actual") ? { actual: String(detail.actual) } : {}
      });
      if (this.errors)
        this.errors.append(error);
      else
        this.errors = error;
      return error;
    }
    mustBe(expectation) {
      this.expectation = expectation;
      return false;
    }
    reject(input) {
      if (typeof input === "string") {
        this.expectation = input;
        return false;
      }
      this.error(input);
      return false;
    }
  }
  var kBase = Symbol("omptype.base");
  var kSteps = Symbol("omptype.steps");
  var EMPTY_STEPS = [];
  var EMPTY_META = {};
  var ARK_COMPAT_SCOPE = Object.freeze({ internal: Object.freeze({ name: "ark" }) });
  var JIT_THRESHOLD = 3;
  function metaOf(schema) {
    return {
      description: schema.description,
      defaultValue: schema.defaultValue,
      hasDefault: schema.hasDefault,
      defaultOutput: schema.defaultOutput,
      hasDefaultOutput: schema.hasDefaultOutput,
      errorConfig: schema.errorConfig,
      clone: schema.clone
    };
  }
  function inheritScope(source, target) {
    if (source.resolver === undefined)
      return target;
    target.resolver = source.resolver;
    Reflect.set(target, "$", source.$);
    return target;
  }
  function invalidDefault(label, errors) {
    const error = errors[0];
    let heading = label;
    for (let index = 0;index < error.path.length; index++) {
      const segment = error.path[index];
      if (typeof segment === "number") {
        if (label === "Default" && index === 0)
          heading = "Default value";
        heading += ` at [${segment}]`;
      } else if (label === "Default" && index === 0) {
        heading += ` ${String(segment)}`;
      } else {
        heading += `.${String(segment)}`;
      }
    }
    throw new OmpTypeError(`ParseError: ${heading} ${error.problem}`);
  }
  function rejectMutableStaticDefault(value) {
    if (value !== null && typeof value === "object" && !(value instanceof Date)) {
      throw new OmpTypeError("ParseError: A mutable default value must be specified as a factory");
    }
  }
  function normalizeDefaults(ir, seen = new WeakSet) {
    if (seen.has(ir))
      return;
    seen.add(ir);
    switch (ir.k) {
      case "object":
        for (const prop of ir.props) {
          normalizeDefaults(prop.val, seen);
          if (!prop.hasDefault || prop.defValidated)
            continue;
          let candidate;
          let factory = false;
          if (prop.defFactory && typeof prop.def === "function") {
            candidate = prop.def();
            factory = true;
          } else {
            rejectMutableStaticDefault(prop.def);
            candidate = prop.def;
          }
          const output = walk(prop.val, candidate);
          if (output instanceof OmpErrors)
            invalidDefault(`Default for ${String(prop.key)}`, output);
          if (!factory)
            prop.def = output;
          prop.defValidated = true;
        }
        if (ir.index)
          normalizeDefaults(ir.index, seen);
        if (ir.symbolIndex)
          normalizeDefaults(ir.symbolIndex, seen);
        if (ir.patternIndexes) {
          for (const index of ir.patternIndexes) {
            normalizeDefaults(index.key, seen);
            normalizeDefaults(index.val, seen);
          }
        }
        return;
      case "tuple":
        for (let index = 0;index < ir.prefix.length; index++) {
          const item = ir.prefix[index];
          normalizeDefaults(item.val, seen);
          if (!item.hasDefault || item.defValidated)
            continue;
          let candidate;
          let factory = false;
          if (item.defFactory && typeof item.def === "function") {
            candidate = item.def();
            factory = true;
          } else {
            rejectMutableStaticDefault(item.def);
            candidate = item.def;
          }
          const output = walk(item.val, candidate);
          if (output instanceof OmpErrors)
            invalidDefault(`Default for [${index}]`, output);
          if (!factory)
            item.def = output;
          item.defValidated = true;
        }
        if (ir.variadic)
          normalizeDefaults(ir.variadic, seen);
        for (const item of ir.postfix)
          normalizeDefaults(item, seen);
        return;
      case "array":
        normalizeDefaults(ir.el, seen);
        return;
      case "union":
      case "intersection":
        for (const member of ir.members)
          normalizeDefaults(member, seen);
        return;
      case "refine":
        normalizeDefaults(ir.base, seen);
        return;
      case "morph":
        normalizeDefaults(ir.input, seen);
        if (ir.out)
          normalizeDefaults(ir.out, seen);
        return;
      default:
        return;
    }
  }
  var OPAQUE_OUTPUT_IR = { k: "unknown" };
  var typeMethods = {
    describe(description) {
      const ir = { ...this.ir, desc: description, cfg: { ...this.ir.cfg, expected: description } };
      return makeType(ir, this[kSteps], { ...metaOf(this), description });
    },
    configure(config, selector = "self") {
      const selected = selector === "self" ? configureNode(this.ir, config) : configureSelected(this.ir, config, selector);
      return makeType(selected, this[kSteps], {
        ...metaOf(this),
        errorConfig: { ...this.errorConfig, ...errorConfigOf(config) },
        ...config.description === undefined ? {} : { description: config.description }
      });
    },
    default(value) {
      const factory = typeof value === "function";
      if (!factory)
        rejectMutableStaticDefault(value);
      const candidate = factory ? value() : value;
      const output = this.run(candidate);
      if (output instanceof OmpErrors)
        invalidDefault("Default", output);
      return makeType(this.ir, this[kSteps], {
        ...metaOf(this),
        defaultValue: value,
        hasDefault: true,
        ...factory ? {} : { defaultOutput: output, hasDefaultOutput: true }
      });
    },
    optional() {
      return [this, "?"];
    },
    or(def) {
      const other = parseDef(def, this.resolver);
      const a = embed(this);
      const members = [...a.k === "union" ? a.members : [a], ...other.k === "union" ? other.members : [other]];
      return inheritScope(this, makeType({ k: "union", members }, [], {}));
    },
    equals(def) {
      return irEquals(embed(this), parseDef(def, this.resolver));
    },
    ifEquals(def) {
      return irEquals(embed(this), parseDef(def, this.resolver)) ? this : undefined;
    },
    ifExtends(def) {
      return isSubtype(embed(this), parseDef(def, this.resolver)) ? this : undefined;
    },
    extends(def) {
      return isSubtype(embed(this), parseDef(def, this.resolver));
    },
    overlaps(def) {
      try {
        intersect(embed(this), parseDef(def, this.resolver));
        return true;
      } catch (error) {
        if (error instanceof OmpTypeError)
          return false;
        throw error;
      }
    },
    distribute(mapper, reducer) {
      const branches = this.ir.k === "union" ? this.ir.members : [embed(this)];
      const mapped = branches.map((branch) => mapper(makeType(branch, [], {})));
      if (reducer !== undefined)
        return reducer(mapped);
      const members = mapped.map((branch) => embed(branch));
      return makeType(members.length === 1 ? members[0] : { k: "union", members }, [], {});
    },
    select(kind) {
      return selectNodes(this.ir, kind);
    },
    and(def) {
      return inheritScope(this, makeType(intersect(embed(this), parseDef(def, this.resolver)), [], {}));
    },
    array() {
      return inheritScope(this, makeType({ k: "array", el: embed(this) }, [], {}));
    },
    atLeastLength(bound) {
      return makeType(withLengthBound(this.ir, "min", bound), this[kSteps], metaOf(this));
    },
    atMostLength(bound) {
      return makeType(withLengthBound(this.ir, "max", bound), this[kSteps], metaOf(this));
    },
    moreThanLength(bound) {
      return makeType(withLengthBound(this.ir, "min", bound + 1), this[kSteps], metaOf(this));
    },
    lessThanLength(bound) {
      return makeType(withLengthBound(this.ir, "max", bound - 1), this[kSteps], metaOf(this));
    },
    exactlyLength(bound) {
      const bounded = withLengthBound(withLengthBound(this.ir, "min", bound), "max", bound);
      return makeType(bounded, this[kSteps], metaOf(this));
    },
    atLeast(bound) {
      return makeType(withNumericBound(this.ir, "min", bound), this[kSteps], metaOf(this));
    },
    atMost(bound) {
      return makeType(withNumericBound(this.ir, "max", bound), this[kSteps], metaOf(this));
    },
    moreThan(bound) {
      return makeType(withNumericBound(this.ir, "min", bound, true), this[kSteps], metaOf(this));
    },
    lessThan(bound) {
      return makeType(withNumericBound(this.ir, "max", bound, true), this[kSteps], metaOf(this));
    },
    divisibleBy(divisor) {
      if (this.ir.k !== "number")
        throw new OmpTypeError(`cannot apply divisibility to ${this.ir.k}`);
      if (!Number.isFinite(divisor) || divisor === 0)
        throw new OmpTypeError("divisor must be non-zero");
      return makeType({ ...this.ir, divisor }, this[kSteps], metaOf(this));
    },
    positive() {
      return makeType(withNumericBound(this.ir, "min", 0, true), this[kSteps], metaOf(this));
    },
    negative() {
      return makeType(withNumericBound(this.ir, "max", 0, true), this[kSteps], metaOf(this));
    },
    nonNegative() {
      return makeType(withNumericBound(this.ir, "min", 0), this[kSteps], metaOf(this));
    },
    nonPositive() {
      return makeType(withNumericBound(this.ir, "max", 0), this[kSteps], metaOf(this));
    },
    matching(pattern) {
      return makeType(intersect(this.ir, patternIR(pattern)), this[kSteps], metaOf(this));
    },
    atOrAfter(bound) {
      const timestamp = bound instanceof Date ? bound.valueOf() : bound;
      return dateRefinement(this, timestamp, "at or after", (value) => value >= timestamp);
    },
    atOrBefore(bound) {
      const timestamp = bound instanceof Date ? bound.valueOf() : bound;
      return dateRefinement(this, timestamp, "at or before", (value) => value <= timestamp);
    },
    laterThan(bound) {
      const timestamp = bound instanceof Date ? bound.valueOf() : bound;
      return dateRefinement(this, timestamp, "later than", (value) => value > timestamp);
    },
    earlierThan(bound) {
      const timestamp = bound instanceof Date ? bound.valueOf() : bound;
      return dateRefinement(this, timestamp, "earlier than", (value) => value < timestamp);
    },
    pipe(...pipes) {
      return appendPipes(this, pipes, false);
    },
    to(def) {
      return appendPipes(this, [makeType(parseDef(def, this.resolver), [], {})], false, true);
    },
    filter(fn) {
      return makeType(this.ir, [{ kind: "filter", fn }, ...this[kSteps]], metaOf(this));
    },
    narrow(fn) {
      return makeType(this.ir, [...this[kSteps], { kind: "narrow", fn }], metaOf(this));
    },
    brand() {
      return this;
    },
    as() {
      return this;
    },
    readonly() {
      return this;
    },
    keyof() {
      return makeType(keyOf(this.ir), [], {});
    },
    get(...path) {
      if (path.length === 0)
        return this;
      let result = this.ir;
      for (const key of path)
        result = getPathIR(result, key);
      return makeType(result, [], {});
    },
    pick(...keys) {
      return makeType(selectObjectProps(this.ir, keys, true, "pick"), [], {});
    },
    omit(...keys) {
      return makeType(selectObjectProps(this.ir, keys, false, "omit"), [], {});
    },
    partial() {
      return makeType(setObjectOptionality(this.ir, true, "partial"), [], {});
    },
    required() {
      return makeType(setObjectOptionality(this.ir, false, "required"), [], {});
    },
    map(mapper) {
      const object = requireObject(this.ir, "map");
      const props = object.props.flatMap((prop) => {
        const original = propertyFromIR(prop);
        const mapped = mapper(original);
        return (Array.isArray(mapped) ? mapped : [mapped]).map((property) => propertyToIR(property.kind === "required" || property.kind === "optional" ? property : { ...property, kind: original.kind }));
      });
      return makeType({ ...object, props }, [], {});
    },
    merge(def) {
      const merged = mergeObjectDefinition(this.ir, def, this.resolver);
      return inheritScope(this, makeType(merged, [], {}));
    },
    extract(def) {
      return inheritScope(this, makeType(distributeFilter(this.ir, parseDef(def, this.resolver), true), [], {}));
    },
    exclude(def) {
      return inheritScope(this, makeType(distributeFilter(this.ir, parseDef(def, this.resolver), false), [], {}));
    },
    onUndeclaredKey(behavior) {
      const extras = behavior === "ignore" ? "keep" : behavior;
      const ir = withShallowExtras(this.ir, extras);
      if (extras === "delete" && ir.k === "union") {
        const objects = ir.members.filter((member) => member.k === "object");
        for (let left = 0;left < objects.length; left++) {
          for (let right = left + 1;right < objects.length; right++) {
            const sharedRequired = objects[left].props.some((leftProp) => !leftProp.opt && objects[right].props.some((rightProp) => !rightProp.opt && rightProp.key === leftProp.key));
            if (!sharedRequired) {
              const leftExpression = expressionOf(objects[left]).replace(/ }$/, ", + (undeclared): delete }");
              const rightExpression = expressionOf(objects[right]).replace(/ }$/, ", + (undeclared): delete }");
              throw new OmpTypeError(`ParseError: An unordered union of a type including a morph and a type with overlapping input is indeterminate:
Left: ${leftExpression}
Right: ${rightExpression}`);
            }
          }
        }
      }
      return makeType(ir, this[kSteps], metaOf(this));
    },
    onDeepUndeclaredKey(behavior) {
      return makeType(withDeepExtras(this.ir, behavior === "ignore" ? "keep" : behavior), this[kSteps], metaOf(this));
    },
    allows(data) {
      const steps = this[kSteps];
      let needsPredicates = false;
      for (const step of steps) {
        if (step.kind !== "pipe") {
          needsPredicates = true;
          break;
        }
      }
      if (!needsPredicates) {
        const allows = compileAllows(this.ir);
        this.allows = allows;
        return allows(data);
      }
      for (const step of steps) {
        if (step.kind === "filter" && !step.fn(data, new Ctx(data)))
          return false;
      }
      const out = this[kBase](data);
      if (out instanceof OmpErrors)
        return false;
      for (const step of steps) {
        if (step.kind === "narrow" && !step.fn(out, new Ctx(out)))
          return false;
      }
      return true;
    },
    assert(data) {
      const out = this.run(data);
      if (out instanceof OmpErrors)
        throw new TraversalError(out);
      return out;
    },
    from(data) {
      const out = this.run(data);
      if (out instanceof OmpErrors)
        throw new TraversalError(out);
      return out;
    },
    toJsonSchema(options) {
      const ir = options?.io === "output" ? this.opaqueOutput ? OPAQUE_OUTPUT_IR : this.stepOut ?? this.ir : this.ir;
      const description = options?.description ?? this.ir.desc;
      if (description === undefined)
        return irToJsonSchema(ir, options);
      return irToJsonSchema(ir, { ...options, description });
    }
  };
  Object.defineProperty(typeMethods, "expression", {
    get() {
      const input = expressionOf(this.ir);
      if (!this.hasSteps)
        return input;
      if (this.opaqueOutput)
        return `(In: ${input}) => Out<unknown>`;
      return `(In: ${input}) => To<${expressionOf(this.stepOut ?? this.ir)}>`;
    }
  });
  Object.defineProperty(typeMethods, "json", {
    get() {
      return arkJsonOf(this.ir);
    }
  });
  Object.defineProperty(typeMethods, "props", {
    get() {
      const object = requireObject(this.ir, "props");
      return object.props.map((prop) => propertyFromIR(prop));
    }
  });
  Object.defineProperty(typeMethods, "~standard", {
    get() {
      const jsonSchema = (io, options) => {
        if (options.target !== "draft-2020-12" && options.target !== "draft-07") {
          throw new OmpTypeError(`JSONSchema target '${options.target}' is not supported (must be "draft-2020-12" or "draft-07")`);
        }
        return this.toJsonSchema({ ...options.libraryOptions, target: options.target, io });
      };
      return {
        version: 1,
        vendor: "omptype",
        validate: (value) => {
          const out = this.run(value);
          return out instanceof OmpErrors ? { issues: out } : { value: out };
        },
        jsonSchema: {
          input: (options) => jsonSchema("input", options),
          output: (options) => jsonSchema("output", options)
        }
      };
    }
  });
  Object.defineProperty(typeMethods, "in", {
    get() {
      return makeType(projectIO(this.ir, "in"), [], {});
    }
  });
  Object.defineProperty(typeMethods, "out", {
    get() {
      if (this.opaqueOutput)
        return makeType({ k: "unknown" }, [], {});
      return makeType(projectIO(this.stepOut ?? this.ir, "out"), [], {});
    }
  });
  var allowsMethod = typeMethods.allows;
  var assertMethod = typeMethods.assert;
  var fromMethod = typeMethods.from;
  Object.defineProperties(typeMethods, {
    description: {
      get() {
        return descriptionOf(this.ir);
      }
    },
    allows: {
      get() {
        const allows = (data) => allowsMethod.call(this, data);
        Object.defineProperty(this, "allows", { value: allows, writable: true });
        return allows;
      }
    },
    assert: {
      get() {
        const assert = assertMethod.bind(this);
        Object.defineProperty(this, "assert", { value: assert });
        return assert;
      }
    },
    from: {
      get() {
        const from = fromMethod.bind(this);
        Object.defineProperty(this, "from", { value: from });
        return from;
      }
    },
    pipe: {
      get() {
        const pipe = Object.assign((...pipes) => appendPipes(this, pipes, false), {
          try: (...pipes) => appendPipes(this, pipes, true)
        });
        Object.defineProperty(this, "pipe", { value: pipe });
        return pipe;
      }
    }
  });
  Object.setPrototypeOf(typeMethods, Function.prototype);
  Object.defineProperty(typeMethods, "bind", { value: undefined });
  function makeType(ir, steps, meta) {
    let morph = false;
    if (!isSimpleIR(ir)) {
      ir = normalizeIR(ir);
      morph = hasMorph(ir);
      if (morph) {
        normalizeDefaults(ir);
        assertDeterminateMorphUnions(ir);
      }
    }
    let calls = 0;
    let impl = (data) => {
      if (++calls >= JIT_THRESHOLD) {
        impl = compile(ir);
        return impl(data);
      }
      return walk(ir, data);
    };
    const base = (data) => impl(data);
    const errorConfig = meta.errorConfig ?? ir.cfg;
    const filterInput = steps.some((step) => step.kind === "filter") ? projectIO(ir, "in") : undefined;
    const validate = steps.length === 0 ? base : (data, contextPath = []) => {
      if (filterInput !== undefined) {
        const inputResult = walk(filterInput, data);
        if (inputResult instanceof OmpErrors)
          return inputResult;
      }
      for (const step of steps) {
        if (step.kind !== "filter")
          continue;
        const ctx = new Ctx(data, contextPath);
        const result = step.fn(data, ctx);
        if (result instanceof OmpErrors)
          return errorConfig === undefined ? result : result.configure(errorConfig);
        if (ctx.errors)
          return errorConfig === undefined ? ctx.errors : ctx.errors.configure(errorConfig);
        if (!result) {
          return OmpErrors.single([], ctx.expectation ?? (step.fn.name ? `valid according to ${step.fn.name}` : "valid (input predicate failed)"), data, errorConfig);
        }
      }
      let out = base(data);
      if (out instanceof OmpErrors)
        return out;
      for (const step of steps) {
        if (step.kind === "filter")
          continue;
        const ctx = new Ctx(out, contextPath);
        if (step.kind === "narrow") {
          const result = step.fn(out, ctx);
          if (result instanceof OmpErrors) {
            return errorConfig === undefined ? result : result.configure(errorConfig);
          }
          if (ctx.errors)
            return errorConfig === undefined ? ctx.errors : ctx.errors.configure(errorConfig);
          if (!result) {
            return OmpErrors.single([], ctx.expectation ?? (step.fn.name ? `valid according to ${step.fn.name}` : "valid (narrow predicate failed)"), out, errorConfig);
          }
        } else {
          try {
            out = step.fn(out, ctx);
          } catch (error) {
            if (!step.try)
              throw error;
            const detail = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
            return OmpErrors.single([], `valid (morph threw ${detail})`, out, errorConfig);
          }
          if (out instanceof OmpErrors) {
            return errorConfig === undefined ? out : out.configure(errorConfig);
          }
        }
      }
      return out;
    };
    const needsClone = morph || steps.some((step) => step.kind === "pipe");
    const clone = meta.clone;
    let callable = validate;
    if (needsClone && clone !== undefined) {
      if (clone === false) {
        callable = (data, path) => {
          const out = validate(data, path);
          if (out instanceof OmpErrors || out === data || typeof data !== "object" || data === null || typeof out !== "object" || out === null) {
            return out;
          }
          if (Array.isArray(data) && Array.isArray(out)) {
            data.splice(0, data.length, ...out);
          } else {
            const target = data;
            const source = out;
            for (const key of Reflect.ownKeys(target)) {
              if (!Object.hasOwn(source, key))
                Reflect.deleteProperty(target, key);
            }
            for (const key of Reflect.ownKeys(source))
              target[key] = source[key];
          }
          return data;
        };
      } else {
        callable = (data, path) => validate(clone(data), path);
      }
    }
    if (meta.hasDefault === true) {
      const inner = callable;
      const value = meta.defaultValue;
      callable = (data, path) => {
        if (data !== undefined)
          return inner(data, path);
        if (meta.hasDefaultOutput === true)
          return meta.defaultOutput;
        return inner(typeof value === "function" ? value() : value, path);
      };
    }
    const self2 = callable;
    self2[IR_BRAND] = true;
    self2[kBase] = base;
    self2[kSteps] = steps;
    self2.ir = ir;
    self2.hasSteps = steps.length > 0;
    self2.hasDefault = meta.hasDefault === true;
    self2.defaultValue = meta.defaultValue;
    self2.defaultOutput = meta.defaultOutput;
    self2.hasDefaultOutput = meta.hasDefaultOutput === true;
    self2.errorConfig = meta.errorConfig ?? ir.cfg;
    self2.clone = meta.clone;
    self2.run = callable;
    self2.$ = ARK_COMPAT_SCOPE;
    for (let i = steps.length - 1;i >= 0; i--) {
      const step = steps[i];
      if (step.kind !== "pipe")
        continue;
      self2.stepOut = step.out;
      self2.opaqueOutput = step.out === undefined;
      break;
    }
    Object.setPrototypeOf(self2, typeMethods);
    return self2;
  }
  function appendPipes(source, pipes, catchErrors, forcePipeline = false) {
    let schema = source;
    for (const candidate of pipes) {
      const isSchema = (typeof candidate === "function" || typeof candidate === "object" && candidate !== null) && IR_BRAND in candidate;
      if (isSchema) {
        const target = candidate;
        if (!forcePipeline && schema[kSteps].length === 0 && !target.hasSteps && !hasMorph(schema.ir) && !hasMorph(target.ir)) {
          schema = makeType(intersect(schema.ir, target.ir), [], metaOf(schema));
          continue;
        }
        const out = target.opaqueOutput ? undefined : target.stepOut ?? target.ir;
        schema = makeType(schema.ir, [...schema[kSteps], { kind: "pipe", fn: (value) => target.run(value), out, try: catchErrors }], metaOf(schema));
        continue;
      }
      if (typeof candidate !== "function")
        throw new OmpTypeError("pipe operands must be functions or Types");
      schema = makeType(schema.ir, [...schema[kSteps], { kind: "pipe", fn: candidate, try: catchErrors }], metaOf(schema));
    }
    return inheritScope(source, schema);
  }
  function projectIO(ir, io) {
    switch (ir.k) {
      case "morph":
        return projectIO(io === "in" || ir.out === undefined ? ir.input : ir.out, io);
      case "sub":
        if (io === "out" && ir.schema.opaqueOutput)
          return { k: "unknown" };
        return projectIO(io === "out" ? ir.schema.stepOut ?? ir.schema.ir : ir.schema.ir, io);
      case "array":
        return { ...ir, el: projectIO(ir.el, io) };
      case "tuple":
        return {
          ...ir,
          prefix: ir.prefix.map((item) => ({
            ...item,
            opt: io === "in" ? item.opt || item.hasDefault === true : item.opt && !item.hasDefault,
            val: projectIO(item.val, io),
            hasDefault: false,
            def: undefined,
            defFactory: false,
            defValidated: false
          })),
          variadic: ir.variadic === undefined ? undefined : projectIO(ir.variadic, io),
          postfix: ir.postfix.map((item) => projectIO(item, io))
        };
      case "object":
        return {
          ...ir,
          props: ir.props.map((prop) => ({
            ...prop,
            opt: io === "in" ? prop.opt || prop.hasDefault === true : prop.opt && !prop.hasDefault,
            val: projectIO(prop.val, io),
            hasDefault: false,
            def: undefined,
            defFactory: false,
            defValidated: false
          })),
          index: ir.index === undefined ? undefined : projectIO(ir.index, io),
          symbolIndex: ir.symbolIndex === undefined ? undefined : projectIO(ir.symbolIndex, io),
          patternIndexes: ir.patternIndexes?.map((index) => ({
            key: projectIO(index.key, io),
            val: projectIO(index.val, io)
          })),
          extras: ir.extras === "delete" ? io === "in" ? "keep" : "reject" : ir.extras
        };
      case "union":
      case "intersection":
        return { ...ir, members: ir.members.map((member) => projectIO(member, io)) };
      case "refine":
        return { ...ir, base: projectIO(ir.base, io) };
      case "alias":
        return { ...ir, resolve: () => projectIO(ir.resolve(), io) };
      default:
        return ir;
    }
  }
  function morphIdentities(ir, identities = [], seen = new Set) {
    if (seen.has(ir))
      return identities;
    seen.add(ir);
    switch (ir.k) {
      case "morph":
        identities.push(ir.out === undefined ? ir.fn : `declared:${expressionOf(projectIO(ir.input, "in"))}=>${expressionOf(projectIO(ir.out, "out"))}`);
        morphIdentities(ir.input, identities, seen);
        if (ir.out !== undefined)
          morphIdentities(ir.out, identities, seen);
        break;
      case "sub": {
        const schema = ir.schema;
        for (const step of schema[kSteps])
          if (step.kind === "pipe")
            identities.push(step.fn);
        morphIdentities(schema.ir, identities, seen);
        break;
      }
      case "array":
        morphIdentities(ir.el, identities, seen);
        break;
      case "tuple":
        for (const item of ir.prefix)
          morphIdentities(item.val, identities, seen);
        if (ir.variadic !== undefined)
          morphIdentities(ir.variadic, identities, seen);
        for (const item of ir.postfix)
          morphIdentities(item, identities, seen);
        break;
      case "object":
        if (ir.extras === "delete")
          identities.push(ir);
        for (const prop of ir.props)
          morphIdentities(prop.val, identities, seen);
        if (ir.index !== undefined)
          morphIdentities(ir.index, identities, seen);
        if (ir.symbolIndex !== undefined)
          morphIdentities(ir.symbolIndex, identities, seen);
        for (const index of ir.patternIndexes ?? [])
          morphIdentities(index.val, identities, seen);
        break;
      case "union":
      case "intersection":
        for (const member of ir.members)
          morphIdentities(member, identities, seen);
        break;
      case "refine":
        morphIdentities(ir.base, identities, seen);
        break;
      case "alias":
        morphIdentities(ir.resolve(), identities, seen);
        break;
    }
    return identities;
  }
  function assertDeterminateMorphUnions(ir, seen = new Set) {
    if (seen.has(ir))
      return;
    seen.add(ir);
    if (ir.k === "union") {
      for (let leftIndex = 0;leftIndex < ir.members.length; leftIndex++) {
        const left = ir.members[leftIndex];
        const leftMorphs = morphIdentities(left);
        for (let rightIndex = leftIndex + 1;rightIndex < ir.members.length; rightIndex++) {
          const right = ir.members[rightIndex];
          const rightMorphs = morphIdentities(right);
          if (leftMorphs.length === 0 && rightMorphs.length === 0)
            continue;
          if (leftMorphs.length === rightMorphs.length && leftMorphs.every((identity, index) => identity === rightMorphs[index])) {
            continue;
          }
          let leftInput = projectIO(left, "in");
          let rightInput = projectIO(right, "in");
          if (leftInput.k === "alias")
            leftInput = leftInput.resolve();
          if (rightInput.k === "alias")
            rightInput = rightInput.resolve();
          if (leftInput.k === "object" && rightInput.k === "object") {
            const leftKeys = new Set(leftInput.props.map((prop) => prop.key));
            const rightKeys = new Set(rightInput.props.map((prop) => prop.key));
            const leftRejectsRequiredRight = leftInput.extras === "reject" && rightInput.props.some((prop) => !prop.opt && !prop.hasDefault && !leftKeys.has(prop.key));
            const rightRejectsRequiredLeft = rightInput.extras === "reject" && leftInput.props.some((prop) => !prop.opt && !prop.hasDefault && !rightKeys.has(prop.key));
            if (leftRejectsRequiredRight || rightRejectsRequiredLeft)
              continue;
          }
          try {
            intersect(leftInput, rightInput);
          } catch (error) {
            if (error instanceof OmpTypeError)
              continue;
            throw error;
          }
          throw new OmpTypeError("an unordered union with overlapping morph inputs is indeterminate");
        }
      }
    }
    switch (ir.k) {
      case "alias":
        assertDeterminateMorphUnions(ir.resolve(), seen);
        break;
      case "morph":
        assertDeterminateMorphUnions(ir.input, seen);
        if (ir.out !== undefined)
          assertDeterminateMorphUnions(ir.out, seen);
        break;
      case "sub":
        assertDeterminateMorphUnions(ir.schema.ir, seen);
        break;
      case "array":
        assertDeterminateMorphUnions(ir.el, seen);
        break;
      case "tuple":
        for (const item of ir.prefix)
          assertDeterminateMorphUnions(item.val, seen);
        if (ir.variadic !== undefined)
          assertDeterminateMorphUnions(ir.variadic, seen);
        for (const item of ir.postfix)
          assertDeterminateMorphUnions(item, seen);
        break;
      case "object":
        for (const prop of ir.props)
          assertDeterminateMorphUnions(prop.val, seen);
        if (ir.index !== undefined)
          assertDeterminateMorphUnions(ir.index, seen);
        if (ir.symbolIndex !== undefined)
          assertDeterminateMorphUnions(ir.symbolIndex, seen);
        for (const index of ir.patternIndexes ?? [])
          assertDeterminateMorphUnions(index.val, seen);
        break;
      case "union":
      case "intersection":
        for (const member of ir.members)
          assertDeterminateMorphUnions(member, seen);
        break;
      case "refine":
        assertDeterminateMorphUnions(ir.base, seen);
        break;
    }
  }
  function getPathIR(ir, requestedKey) {
    let key = requestedKey;
    if ((typeof key === "function" || typeof key === "object" && key !== null) && IR_BRAND in key) {
      const keySchema = key;
      if (keySchema.ir.k === "symbol")
        key = Symbol.for("omptype.index");
      else {
        const arrayIndex = type.arrayIndex;
        if (keySchema === arrayIndex)
          key = 0;
        else {
          throw new OmpTypeError(`${keySchema.expression} is not allowed as an array or object index; use a concrete property key`);
        }
      }
    }
    if (typeof key !== "string" && typeof key !== "number" && typeof key !== "symbol") {
      throw new OmpTypeError(`get keys must be strings, numbers, or symbols`);
    }
    if (ir.k === "alias")
      return getPathIR(ir.resolve(), key);
    if (ir.k === "sub")
      return getPathIR(ir.schema.ir, key);
    if (ir.k === "union") {
      return unionOf(ir.members.map((member) => getPathIR(member, key)));
    }
    if (ir.k === "array") {
      const index = typeof key === "number" ? key : typeof key === "string" && /^\d+$/.test(key) ? Number(key) : -1;
      if (!Number.isSafeInteger(index) || index < 0)
        throw new OmpTypeError(`key ${String(key)} is not declared`);
      return unionOf([ir.el, { k: "undefined" }]);
    }
    if (ir.k === "tuple") {
      const index = typeof key === "number" ? key : typeof key === "string" && /^\d+$/.test(key) ? Number(key) : -1;
      if (!Number.isSafeInteger(index) || index < 0)
        throw new OmpTypeError(`key ${String(key)} is not declared`);
      if (index < ir.prefix.length) {
        const item = ir.prefix[index];
        return item.opt ? unionOf([{ k: "undefined" }, item.val]) : item.val;
      }
      if (ir.variadic === undefined)
        throw new OmpTypeError(`key ${String(key)} is not declared`);
      return unionOf([{ k: "undefined" }, ir.variadic, ...ir.postfix]);
    }
    if (ir.k === "undefined")
      return ir;
    if (ir.k !== "object")
      throw new OmpTypeError("get requires an object schema");
    const matches = [];
    const prop = ir.props.find((candidate) => candidate.key === String(key));
    if (prop !== undefined)
      matches.push(prop.val);
    if (typeof key === "string") {
      if (ir.index !== undefined)
        matches.push(ir.index);
      for (const index of ir.patternIndexes ?? []) {
        if (!(walk(index.key, key) instanceof OmpErrors))
          matches.push(index.val);
      }
    } else if (typeof key === "symbol" && ir.symbolIndex !== undefined) {
      matches.push(ir.symbolIndex);
    }
    if (matches.length === 0)
      throw new OmpTypeError(`key ${String(key)} is not declared`);
    const value = matches.reduce((left, right) => intersect(left, right));
    return prop !== undefined && !prop.opt ? value : unionOf([value, { k: "undefined" }]);
  }
  function unionOf(members) {
    const flattened = members.flatMap((member) => member.k === "union" ? member.members : [member]);
    return flattened.length === 1 ? flattened[0] : { k: "union", members: flattened };
  }
  function expressionOf(ir, ancestors = new Set) {
    if (ancestors.has(ir))
      return ir.k === "alias" ? ir.name : ir.k;
    const nextAncestors = new Set(ancestors);
    nextAncestors.add(ir);
    const child = (node) => expressionOf(node, nextAncestors);
    switch (ir.k) {
      case "alias":
        return child(ir.resolve());
      case "sub":
        return child(ir.schema.ir);
      case "unknown":
      case "null":
      case "undefined":
      case "boolean":
      case "bigint":
      case "symbol":
      case "never":
        return ir.k;
      case "anyobject":
        return "object";
      case "string":
        return "string";
      case "number":
        return ir.divisor !== undefined ? `number % ${ir.divisor}` : ir.int ? "number % 1" : "number";
      case "lit":
        return typeof ir.v === "string" ? JSON.stringify(ir.v) : String(ir.v);
      case "array": {
        const element = child(ir.el);
        return `${ir.el.k === "union" || ir.el.k === "intersection" ? `(${element})` : element}[]`;
      }
      case "tuple": {
        const items = ir.prefix.map((item) => {
          const value = child(item.val);
          if (item.hasDefault)
            return `${value} = ${child({ k: "lit", v: item.def })}`;
          return `${value}${item.opt ? "?" : ""}`;
        });
        if (ir.variadic !== undefined)
          items.push(`...${child(ir.variadic)}[]`);
        items.push(...ir.postfix.map(child));
        return `[${items.join(", ")}]`;
      }
      case "object": {
        const properties = ir.props.map((prop) => `${String(prop.key)}${prop.opt ? "?" : ""}: ${child(prop.val)}`);
        if (ir.index !== undefined)
          properties.unshift(`[string]: ${child(ir.index)}`);
        if (ir.symbolIndex !== undefined)
          properties.unshift(`[symbol]: ${child(ir.symbolIndex)}`);
        return `{ ${properties.join(", ")} }`;
      }
      case "union":
        return [...new Set(ir.members.map(child))].join(" | ");
      case "intersection":
        return ir.members.map(child).join(" & ");
      case "refine":
        return child(ir.base);
      case "morph":
        return `(In: ${child(ir.input)}) => Out<${child(ir.out ?? { k: "unknown" })}>`;
      case "instance":
        return ir.ctor.name || "object";
    }
  }
  function arkJsonOf(ir, ancestors = new Set) {
    if (ancestors.has(ir))
      return ir.k === "alias" ? { alias: ir.name } : { cyclic: ir.k };
    const nextAncestors = new Set(ancestors);
    nextAncestors.add(ir);
    const child = (node) => arkJsonOf(node, nextAncestors);
    switch (ir.k) {
      case "alias":
        return child(ir.resolve());
      case "sub":
        return child(ir.schema.ir);
      case "lit":
        return {
          unit: ir.v === undefined ? "undefined" : typeof ir.v === "bigint" ? `${ir.v}n` : ir.v
        };
      case "null":
        return { unit: null };
      case "undefined":
        return { unit: "undefined" };
      case "boolean":
        return [{ unit: false }, { unit: true }];
      case "union":
      case "intersection":
        return ir.members.map(child);
      case "array":
        return { proto: "Array", sequence: child(ir.el) };
      case "tuple":
        return {
          proto: "Array",
          sequence: {
            prefix: ir.prefix.map((item) => child(item.val)),
            ...ir.variadic === undefined ? {} : { variadic: child(ir.variadic) },
            ...ir.postfix.length === 0 ? {} : { postfix: ir.postfix.map(child) }
          }
        };
      case "object":
        return {
          domain: "object",
          required: ir.props.filter((prop) => !prop.opt && !prop.hasDefault).map((prop) => ({ key: prop.key, value: child(prop.val) })),
          optional: ir.props.filter((prop) => prop.opt || prop.hasDefault).map((prop) => ({
            key: prop.key,
            value: child(prop.val),
            ...prop.hasDefault ? {
              default: prop.defFactory && typeof prop.def === "function" ? `$ark.${prop.def.name || "default"}` : prop.def
            } : {}
          }))
        };
      case "refine":
        return child(ir.base);
      case "morph":
        return { in: child(ir.input), ...ir.out === undefined ? {} : { declaredOut: child(ir.out) } };
      case "instance":
        return { proto: ir.ctor.name };
      case "anyobject":
        return { domain: "object" };
      default:
        return ir.k;
    }
  }
  function requireObject(ir, operation) {
    if (ir.k !== "object")
      throw new OmpTypeError(`${operation} requires an object schema`);
    return ir;
  }
  function selectObjectProps(ir, keys, keepSelected, operation) {
    const object = requireObject(ir, operation);
    const selected = new Set(keys);
    for (const key of selected) {
      if (!object.props.some((prop) => prop.key === key))
        throw new OmpTypeError(`key ${String(key)} does not exist`);
    }
    return { ...object, props: object.props.filter((prop) => selected.has(prop.key) === keepSelected) };
  }
  function setObjectOptionality(ir, optional, operation) {
    const object = requireObject(ir, operation);
    return { ...object, props: object.props.map((prop) => ({ ...prop, opt: optional })) };
  }
  function mergeObjectDefinition(ir, definition, resolve) {
    return mergeObjects(requireObject(ir, "merge"), requireObject(parseDef(definition, resolve), "merge"));
  }
  function propertyFromIR(prop) {
    return {
      kind: prop.opt ? "optional" : "required",
      key: prop.key,
      value: makeType(prop.val, [], {}),
      ...prop.hasDefault ? { default: prop.def } : {},
      meta: {}
    };
  }
  function propertyToIR(property) {
    if (property.kind !== "required" && property.kind !== "optional") {
      throw new OmpTypeError(`mapped property ${String(property.key)} has invalid kind`);
    }
    if (!(IR_BRAND in property.value)) {
      throw new OmpTypeError(`mapped property ${String(property.key)} must contain a schema value`);
    }
    const hasDefault = Object.hasOwn(property, "default");
    return {
      key: property.key,
      opt: property.kind === "optional",
      val: embed(property.value),
      ...hasDefault ? { def: property.default, defFactory: typeof property.default === "function", hasDefault: true } : {}
    };
  }
  function acceptsDateIR(ir) {
    if (ir.k === "instance")
      return ir.ctor === Date;
    if (ir.k === "refine")
      return acceptsDateIR(ir.base);
    if (ir.k === "union")
      return ir.members.every(acceptsDateIR);
    return false;
  }
  function dateRefinement(schema, timestamp, relation, predicate) {
    if (!Number.isFinite(timestamp))
      throw new OmpTypeError("date bound must be valid");
    if (!acceptsDateIR(schema.ir))
      throw new OmpTypeError("date bounds require a Date type");
    const bound = new Date(timestamp);
    return makeType({
      k: "refine",
      base: schema.ir,
      pred: (value) => value instanceof Date && predicate(value.valueOf()),
      expected: `a Date ${relation} ${bound.toISOString()}`,
      json: relation.includes("after") ? { minimum: bound.toISOString() } : { maximum: bound.toISOString() }
    }, schema[kSteps], metaOf(schema));
  }
  function selectNodes(root, kind) {
    const selected = [];
    const seen = new Set;
    const visit = (node) => {
      if (seen.has(node))
        return;
      seen.add(node);
      const nodeKind = node.k === "lit" ? "unit" : node.k;
      if (kind === nodeKind || kind === node.k) {
        selected.push(node.k === "lit" ? { kind: nodeKind, node, unit: node.v } : { kind: nodeKind, node });
      }
      switch (node.k) {
        case "alias":
          visit(node.resolve());
          break;
        case "array":
          visit(node.el);
          break;
        case "tuple":
          for (const item of node.prefix)
            visit(item.val);
          if (node.variadic !== undefined)
            visit(node.variadic);
          for (const item of node.postfix)
            visit(item);
          break;
        case "object":
          for (const prop of node.props)
            visit(prop.val);
          if (node.index !== undefined)
            visit(node.index);
          if (node.symbolIndex !== undefined)
            visit(node.symbolIndex);
          for (const index of node.patternIndexes ?? []) {
            visit(index.key);
            visit(index.val);
          }
          break;
        case "union":
        case "intersection":
          for (const member of node.members)
            visit(member);
          break;
        case "refine":
          visit(node.base);
          break;
        case "morph":
          visit(node.input);
          if (node.out !== undefined)
            visit(node.out);
          break;
        case "sub":
          visit(node.schema.ir);
          break;
      }
    };
    visit(root);
    return selected;
  }
  function mergeObjects(left, right) {
    const props = [...left.props];
    for (const prop of right.props) {
      const index = props.findIndex((candidate) => candidate.key === prop.key);
      if (index < 0)
        props.push(prop);
      else
        props[index] = prop;
    }
    return {
      k: "object",
      props,
      index: right.index ?? left.index,
      symbolIndex: right.symbolIndex ?? left.symbolIndex,
      patternIndexes: left.patternIndexes === undefined && right.patternIndexes === undefined ? undefined : [...left.patternIndexes ?? [], ...right.patternIndexes ?? []],
      extras: right.extras === "keep" ? left.extras : right.extras
    };
  }
  function withShallowExtras(ir, extras) {
    if (ir.k === "object")
      return { ...ir, extras };
    if (ir.k === "union")
      return { ...ir, members: ir.members.map((member) => withShallowExtras(member, extras)) };
    if (ir.k === "alias")
      return withShallowExtras(ir.resolve(), extras);
    throw new OmpTypeError("onUndeclaredKey requires an object schema");
  }
  function withDeepExtras(ir, extras) {
    switch (ir.k) {
      case "object":
        return {
          ...ir,
          extras,
          props: ir.props.map((prop) => ({ ...prop, val: withDeepExtras(prop.val, extras) })),
          index: ir.index === undefined ? undefined : withDeepExtras(ir.index, extras),
          symbolIndex: ir.symbolIndex === undefined ? undefined : withDeepExtras(ir.symbolIndex, extras),
          patternIndexes: ir.patternIndexes?.map((index) => ({
            key: withDeepExtras(index.key, extras),
            val: withDeepExtras(index.val, extras)
          }))
        };
      case "array":
        return { ...ir, el: withDeepExtras(ir.el, extras) };
      case "tuple":
        return {
          ...ir,
          prefix: ir.prefix.map((item) => ({ ...item, val: withDeepExtras(item.val, extras) })),
          variadic: ir.variadic === undefined ? undefined : withDeepExtras(ir.variadic, extras),
          postfix: ir.postfix.map((item) => withDeepExtras(item, extras))
        };
      case "union":
      case "intersection":
        return { ...ir, members: ir.members.map((member) => withDeepExtras(member, extras)) };
      case "refine":
        return { ...ir, base: withDeepExtras(ir.base, extras) };
      case "morph":
        return {
          ...ir,
          input: withDeepExtras(ir.input, extras),
          out: ir.out === undefined ? undefined : withDeepExtras(ir.out, extras)
        };
      default:
        return ir;
    }
  }
  function intersectTupleWithArray(tuple, array) {
    if (array.min !== undefined || array.max !== undefined) {
      return { k: "intersection", members: [tuple, array] };
    }
    return {
      ...tuple,
      prefix: tuple.prefix.map((item) => ({ ...item, val: intersect(item.val, array.el) })),
      variadic: tuple.variadic === undefined ? undefined : intersect(tuple.variadic, array.el),
      postfix: tuple.postfix.map((item) => intersect(item, array.el))
    };
  }
  function intersectTuples(left, right) {
    if (left.postfix.length !== 0 || right.postfix.length !== 0 || left.prefix.some((item) => item.hasDefault) || right.prefix.some((item) => item.hasDefault)) {
      return { k: "intersection", members: [left, right] };
    }
    const leftRequired = left.prefix.filter((item) => !item.opt).length;
    const rightRequired = right.prefix.filter((item) => !item.opt).length;
    const minimum = Math.max(leftRequired, rightRequired);
    const leftMaximum = left.variadic === undefined ? left.prefix.length : Number.POSITIVE_INFINITY;
    const rightMaximum = right.variadic === undefined ? right.prefix.length : Number.POSITIVE_INFINITY;
    const maximum = Math.min(leftMaximum, rightMaximum);
    if (minimum > maximum)
      throw new OmpTypeError("tuple length intersection is unsatisfiable");
    const prefixLength = Number.isFinite(maximum) ? maximum : Math.max(left.prefix.length, right.prefix.length);
    const prefix = [];
    for (let index = 0;index < prefixLength; index++) {
      const leftItem = left.prefix[index];
      const rightItem = right.prefix[index];
      const leftNode = leftItem?.val ?? left.variadic;
      const rightNode = rightItem?.val ?? right.variadic;
      if (leftNode === undefined || rightNode === undefined)
        break;
      const required = leftItem !== undefined && !leftItem.opt || rightItem !== undefined && !rightItem.opt;
      try {
        prefix.push({ val: intersect(leftNode, rightNode), opt: !required });
      } catch (error) {
        if (required || !(error instanceof OmpTypeError))
          throw error;
        break;
      }
    }
    const variadic = leftMaximum === Number.POSITIVE_INFINITY && rightMaximum === Number.POSITIVE_INFINITY ? intersect(left.variadic, right.variadic) : undefined;
    return { k: "tuple", prefix, variadic, postfix: [] };
  }
  var kIntersections = Symbol("omptype.intersections");
  function intersect(a, b) {
    if (a.k === "alias" || b.k === "alias") {
      const target = a;
      target[kIntersections] ??= new WeakMap;
      const cache = target[kIntersections];
      const existing = cache.get(b);
      if (existing !== undefined)
        return existing;
      let resolved;
      const reference = {
        k: "alias",
        name: a.k === "alias" ? a.name : b.k === "alias" ? b.name : "intersection",
        resolve: () => resolved ??= intersectResolved(a.k === "alias" ? a.resolve() : a, b.k === "alias" ? b.resolve() : b)
      };
      cache.set(b, reference);
      return reference;
    }
    return intersectResolved(a, b);
  }
  function intersectResolved(a, b) {
    if (a.k === "never" || b.k === "never")
      throw new OmpTypeError("intersection with never is unsatisfiable");
    if (a.k === "unknown")
      return b;
    if (b.k === "unknown")
      return a;
    if (a === b)
      return a;
    if (a.k === "morph" && b.k === "morph") {
      if (a.fn !== b.fn || a.out !== b.out) {
        throw new OmpTypeError("intersection of distinct morphs is indeterminate");
      }
      return { ...a, input: intersect(a.input, b.input) };
    }
    if (a.k === "morph")
      return { ...a, input: intersect(a.input, b) };
    if (b.k === "morph")
      return { ...b, input: intersect(a, b.input) };
    if (a.k === "sub" && a.schema.hasSteps) {
      if (b.k === "sub" && b.schema.hasSteps) {
        if (a.schema === b.schema)
          return a;
        throw new OmpTypeError("intersection of distinct morphs is indeterminate");
      }
      const schema = a.schema;
      return embed(makeType(intersect(schema.ir, b), schema[kSteps], metaOf(schema)));
    }
    if (b.k === "sub" && b.schema.hasSteps)
      return intersect(b, a);
    if (a.k === "union" || b.k === "union") {
      const union = a.k === "union" ? a : b.k === "union" ? b : undefined;
      if (union === undefined)
        throw new OmpTypeError("union intersection invariant failed");
      const branches = union.members;
      const other = a.k === "union" ? b : a;
      const members = [];
      for (const branch of branches) {
        try {
          members.push(intersect(branch, other));
        } catch (error) {
          if (!(error instanceof OmpTypeError))
            throw error;
        }
      }
      if (members.length === 0)
        throw new OmpTypeError("intersection has no satisfiable branches");
      return members.length === 1 ? members[0] : { k: "union", members };
    }
    if (a.k === "lit") {
      if (walk(b, a.v) instanceof OmpErrors)
        throw new OmpTypeError("literal is excluded by the intersection");
      return a;
    }
    if (b.k === "lit")
      return intersect(b, a);
    if (a.k === "object" && b.k === "object") {
      const props = [...a.props];
      for (const bp of b.props) {
        const index = props.findIndex((prop) => prop.key === bp.key);
        if (index < 0)
          props.push(bp);
        else {
          const ap = props[index];
          const required = !ap.opt && !ap.hasDefault || !bp.opt && !bp.hasDefault;
          if (ap.hasDefault && bp.hasDefault && !Object.is(ap.def, bp.def)) {
            throw new OmpTypeError(`ParseError: Invalid intersection of default values ${String(ap.def)} & ${String(bp.def)}`);
          }
          const defaulted = required ? undefined : ap.hasDefault ? ap : bp.hasDefault ? bp : undefined;
          props[index] = {
            key: ap.key,
            opt: ap.opt && bp.opt,
            val: intersect(ap.val, bp.val),
            ...defaulted ? {
              def: defaulted.def,
              defFactory: defaulted.defFactory,
              hasDefault: true,
              defValidated: defaulted.defValidated
            } : {}
          };
        }
      }
      const extras = a.extras === "reject" || b.extras === "reject" ? "reject" : a.extras === "delete" || b.extras === "delete" ? "delete" : "keep";
      const index = a.index && b.index ? intersect(a.index, b.index) : a.index ?? b.index;
      return { k: "object", props, index, extras };
    }
    if (a.k === "string" && b.k === "string") {
      const min = maxOf(a.min, b.min);
      const max = minOf(a.max, b.max);
      if (min !== undefined && max !== undefined && min > max) {
        throw new OmpTypeError("string length intersection is unsatisfiable");
      }
      return { k: "string", min, max, url: a.url || b.url };
    }
    if (a.k === "number" && b.k === "number") {
      const min = maxOf(a.min, b.min);
      const max = minOf(a.max, b.max);
      const xmin = min !== undefined && (a.min === min && a.xmin === true || b.min === min && b.xmin === true);
      const xmax = max !== undefined && (a.max === max && a.xmax === true || b.max === max && b.xmax === true);
      if (min !== undefined && max !== undefined && (min > max || min === max && (xmin || xmax))) {
        throw new OmpTypeError("numeric range intersection is unsatisfiable");
      }
      if (a.divisor !== undefined && b.divisor !== undefined && a.divisor !== b.divisor) {
        return { k: "intersection", members: [a, b] };
      }
      return {
        k: "number",
        int: a.int || b.int,
        divisor: a.divisor ?? b.divisor,
        min,
        max,
        xmin,
        xmax
      };
    }
    if (a.k === "array" && b.k === "array") {
      const min = maxOf(a.min, b.min);
      const max = minOf(a.max, b.max);
      if (min !== undefined && max !== undefined && min > max) {
        throw new OmpTypeError("array length intersection is unsatisfiable");
      }
      return { k: "array", el: intersect(a.el, b.el), min, max };
    }
    if (a.k === "tuple" && b.k === "tuple")
      return intersectTuples(a, b);
    if (a.k === "tuple" && b.k === "array")
      return intersectTupleWithArray(a, b);
    if (a.k === "array" && b.k === "tuple")
      return intersectTupleWithArray(b, a);
    if (a.k === "instance" && b.k === "instance") {
      if (a.ctor === b.ctor || a.ctor.prototype instanceof b.ctor)
        return a;
      if (b.ctor.prototype instanceof a.ctor)
        return b;
      throw new OmpTypeError(`intersection of ${a.expected} and ${b.expected} is unsatisfiable`);
    }
    if (a.k === b.k && ["null", "undefined", "boolean", "bigint", "symbol", "anyobject"].includes(a.k))
      return a;
    if (a.k === "object" && (b.k === "array" || b.k === "tuple") || b.k === "object" && (a.k === "array" || a.k === "tuple")) {
      return { k: "intersection", members: [a, b] };
    }
    const leftDomain = domainOf(a);
    const rightDomain = domainOf(b);
    if (leftDomain !== undefined && rightDomain !== undefined && leftDomain !== rightDomain) {
      throw new OmpTypeError(`intersection of ${leftDomain} and ${rightDomain} is unsatisfiable`);
    }
    if (a.k === "anyobject" && rightDomain === "object")
      return b;
    if (b.k === "anyobject" && leftDomain === "object")
      return a;
    const members = [...a.k === "intersection" ? a.members : [a], ...b.k === "intersection" ? b.members : [b]];
    return { k: "intersection", members };
  }
  function normalizeIR(ir) {
    switch (ir.k) {
      case "intersection": {
        const members = ir.members.map(normalizeIR);
        if (members.length === 0)
          return { k: "unknown" };
        return members.slice(1).reduce(intersect, members[0]);
      }
      case "union": {
        const members = [];
        let changed = false;
        for (let index = 0;index < ir.members.length; index++) {
          const original = ir.members[index];
          const member = normalizeIR(original);
          changed ||= member !== original;
          if (member.k === "union") {
            members.push(...member.members);
            changed = true;
          } else if (member.k === "never") {
            changed = true;
          } else if (member.k === "unknown") {
            return { k: "unknown" };
          } else {
            members.push(member);
          }
        }
        if (members.every((member) => member.k === "lit" && (member.v === null || typeof member.v !== "object" && typeof member.v !== "function"))) {
          const pruned = [];
          for (const member of members) {
            if (member.k === "lit" && pruned.some((candidate) => candidate.k === "lit" && candidate.v === member.v)) {
              changed = true;
            } else {
              pruned.push(member);
            }
          }
          if (pruned.length === 0)
            return { k: "never" };
          if (pruned.length === 1)
            return pruned[0];
          if (pruned.length === 2 && pruned.every((member) => member.k === "lit" && typeof member.v === "boolean")) {
            return { k: "boolean" };
          }
          return changed ? { ...ir, members: pruned } : ir;
        }
        const pruned = members.filter((member, index) => !members.some((candidate, candidateIndex) => candidateIndex !== index && !hasMorph(member) && !hasMorph(candidate) && isSubtype(member, candidate) && (!isSubtype(candidate, member) || candidateIndex < index)));
        if (pruned.length === 0)
          return { k: "never" };
        if (pruned.length === 1)
          return pruned[0];
        if (pruned.length === 2 && pruned.every((member) => member.k === "lit" && typeof member.v === "boolean")) {
          return { k: "boolean" };
        }
        if (!changed && !pruned.some((member) => member.k === "alias") && pruned.length === ir.members.length && pruned.every((member, index) => member === ir.members[index])) {
          return ir;
        }
        return { ...ir, members: pruned };
      }
      case "array": {
        const element = normalizeIR(ir.el);
        return element === ir.el && ir.el.k !== "alias" ? ir : { ...ir, el: element };
      }
      case "tuple": {
        const prefix = ir.prefix.map((item) => {
          const value = normalizeIR(item.val);
          return value === item.val ? item : { ...item, val: value };
        });
        const variadic = ir.variadic === undefined ? undefined : normalizeIR(ir.variadic);
        const postfix = ir.postfix.map(normalizeIR);
        if (!ir.prefix.some((item) => item.val.k === "alias") && ir.variadic?.k !== "alias" && !ir.postfix.some((item) => item.k === "alias") && prefix.every((item, index) => item === ir.prefix[index]) && variadic === ir.variadic && postfix.every((item, index) => item === ir.postfix[index])) {
          return ir;
        }
        return { ...ir, prefix, variadic, postfix };
      }
      case "object": {
        let props;
        for (let index = 0;index < ir.props.length; index++) {
          const prop = ir.props[index];
          const value = normalizeIR(prop.val);
          if (value === prop.val)
            continue;
          props ??= [...ir.props];
          props[index] = { ...prop, val: value };
        }
        const index = ir.index === undefined ? undefined : normalizeIR(ir.index);
        const symbolIndex = ir.symbolIndex === undefined ? undefined : normalizeIR(ir.symbolIndex);
        const patternIndexes = ir.patternIndexes?.map((pattern) => {
          const key = normalizeIR(pattern.key);
          const val = normalizeIR(pattern.val);
          return key === pattern.key && val === pattern.val ? pattern : { key, val };
        });
        if (props === undefined && !ir.props.some((prop) => prop.val.k === "alias") && ir.index?.k !== "alias" && ir.symbolIndex?.k !== "alias" && !ir.patternIndexes?.some((pattern) => pattern.key.k === "alias" || pattern.val.k === "alias") && index === ir.index && symbolIndex === ir.symbolIndex && patternIndexes?.every((pattern, patternIndex) => pattern === ir.patternIndexes?.[patternIndex]) !== false) {
          return ir;
        }
        return { ...ir, props: props ?? ir.props, index, symbolIndex, patternIndexes };
      }
      case "refine": {
        const base = normalizeIR(ir.base);
        return base === ir.base && ir.base.k !== "alias" ? ir : { ...ir, base };
      }
      case "morph": {
        const input = normalizeIR(ir.input);
        const out = ir.out === undefined ? undefined : normalizeIR(ir.out);
        return input === ir.input && out === ir.out && ir.input.k !== "alias" && ir.out?.k !== "alias" ? ir : { ...ir, input, out };
      }
      case "alias":
        return ir;
      default:
        return ir;
    }
  }
  function domainOf(ir) {
    switch (ir.k) {
      case "null":
        return "null";
      case "undefined":
      case "boolean":
      case "bigint":
      case "symbol":
      case "string":
      case "number":
        return ir.k;
      case "array":
      case "tuple":
        return "array";
      case "object":
      case "anyobject":
      case "instance":
        return "object";
      case "lit":
        return ir.v === null ? "null" : Array.isArray(ir.v) ? "array" : typeof ir.v;
      case "refine":
        return domainOf(ir.base);
      case "morph":
        return domainOf(ir.input);
      case "sub":
        return domainOf(ir.schema.ir);
      case "alias":
        return domainOf(ir.resolve());
      case "union":
      case "intersection": {
        const first = domainOf(ir.members[0] ?? { k: "never" });
        return ir.members.every((member) => domainOf(member) === first) ? first : undefined;
      }
      default:
        return;
    }
  }
  function lowerBoundWithin(source, target) {
    if (target.min === undefined)
      return true;
    if (source.min === undefined || source.min < target.min)
      return false;
    return source.min !== target.min || target.xmin !== true || source.xmin === true;
  }
  function upperBoundWithin(source, target) {
    if (target.max === undefined)
      return true;
    if (source.max === undefined || source.max > target.max)
      return false;
    return source.max !== target.max || target.xmax !== true || source.xmax === true;
  }
  function lengthWithin(source, target) {
    return (target.min === undefined || source.min !== undefined && source.min >= target.min) && (target.max === undefined || source.max !== undefined && source.max <= target.max);
  }
  function isSubtype(source, target, seen = new WeakMap) {
    if (source === target || target.k === "unknown" || source.k === "never")
      return true;
    let targets = seen.get(source);
    if (targets?.has(target))
      return true;
    if (targets === undefined) {
      targets = new Set;
      seen.set(source, targets);
    }
    targets.add(target);
    if (source.k === "alias")
      return isSubtype(source.resolve(), target, seen);
    if (target.k === "alias")
      return isSubtype(source, target.resolve(), seen);
    if (source.k === "union")
      return source.members.every((member) => isSubtype(member, target, seen));
    if (target.k === "union")
      return target.members.some((member) => isSubtype(source, member, seen));
    if (target.k === "intersection")
      return target.members.every((member) => isSubtype(source, member, seen));
    if (source.k === "intersection")
      return source.members.some((member) => isSubtype(member, target, seen));
    if (source.k === "lit")
      return !(walk(target, source.v) instanceof OmpErrors);
    if (source.k === "refine")
      return isSubtype(source.base, target, seen);
    if (source.k === "morph")
      return isSubtype(source.out ?? source.input, target, seen);
    if (source.k === "sub")
      return isSubtype(source.schema.ir, target, seen);
    if (target.k === "refine" || target.k === "morph" || target.k === "sub")
      return false;
    if (source.k === "string" && target.k === "string") {
      return lengthWithin(source, target) && (!target.url || source.url === true);
    }
    if (source.k === "number" && target.k === "number") {
      return lowerBoundWithin(source, target) && upperBoundWithin(source, target) && (!target.int || source.int === true) && (target.divisor === undefined || source.divisor !== undefined && source.divisor % target.divisor === 0);
    }
    if (source.k === "array" && target.k === "array") {
      return lengthWithin(source, target) && isSubtype(source.el, target.el, seen);
    }
    if (source.k === "object" && target.k === "object") {
      for (const targetProp of target.props) {
        const sourceProp = source.props.find((prop) => prop.key === targetProp.key);
        if (sourceProp === undefined) {
          if (!targetProp.opt)
            return false;
          continue;
        }
        if (!targetProp.opt && sourceProp.opt)
          return false;
        if (!isSubtype(sourceProp.val, targetProp.val, seen))
          return false;
      }
      if (target.extras === "reject") {
        if (source.extras !== "reject")
          return false;
        if (target.index === undefined && source.props.some((sourceProp) => !target.props.some((targetProp) => targetProp.key === sourceProp.key))) {
          return false;
        }
      }
      return true;
    }
    if (source.k === "instance" && target.k === "instance") {
      return source.ctor === target.ctor || source.ctor.prototype instanceof target.ctor;
    }
    if (source.k === "object" && target.k === "anyobject")
      return true;
    if (source.k === "instance" && target.k === "anyobject")
      return true;
    if (source.k === "tuple" && target.k === "array") {
      return source.prefix.every((item) => isSubtype(item.val, target.el, seen)) && source.postfix.every((item) => isSubtype(item, target.el, seen)) && (source.variadic === undefined || isSubtype(source.variadic, target.el, seen));
    }
    if (source.k !== target.k)
      return false;
    switch (source.k) {
      case "null":
      case "undefined":
      case "boolean":
      case "bigint":
      case "symbol":
      case "anyobject":
        return true;
      case "tuple":
        return target.k === "tuple" && expectedTuple(source) === expectedTuple(target);
      case "instance":
        return target.k === "instance" && source.ctor === target.ctor;
      default:
        return false;
    }
  }
  function expectedTuple(tuple) {
    return JSON.stringify({
      prefix: tuple.prefix.map((item) => [item.opt, item.hasDefault, expectedOf(item.val)]),
      variadic: tuple.variadic === undefined ? undefined : expectedOf(tuple.variadic),
      postfix: tuple.postfix.map(expectedOf)
    });
  }
  function irEquals(left, right) {
    return isSubtype(left, right) && isSubtype(right, left);
  }
  function maxOf(a, b) {
    if (a === undefined)
      return b;
    if (b === undefined)
      return a;
    return Math.max(a, b);
  }
  function minOf(a, b) {
    if (a === undefined)
      return b;
    if (b === undefined)
      return a;
    return Math.min(a, b);
  }
  function withLengthBound(ir, side, bound) {
    if (ir.k === "array" || ir.k === "string") {
      return side === "min" ? { ...ir, min: bound } : { ...ir, max: bound };
    }
    throw new OmpTypeError(`cannot apply length bound to ${ir.k}`);
  }
  function withNumericBound(ir, side, bound, exclusive = false) {
    if (!Number.isFinite(bound))
      throw new OmpTypeError("numeric bound must be finite");
    if (ir.k === "number") {
      return side === "min" ? { ...ir, min: bound, xmin: exclusive } : { ...ir, max: bound, xmax: exclusive };
    }
    if (ir.k === "union") {
      return { ...ir, members: ir.members.map((member) => withNumericBound(member, side, bound, exclusive)) };
    }
    throw new OmpTypeError(`cannot apply numeric bound to ${ir.k}`);
  }
  var GENERIC_META = Symbol("omptype.generic");
  function validateGenericParameters(parameters) {
    const names = new Set;
    for (const parameter of parameters) {
      if (!/^[A-Za-z_$]\w*$/.test(parameter.name)) {
        throw new OmpTypeError(`invalid generic parameter "${parameter.name}"`);
      }
      if (names.has(parameter.name))
        throw new OmpTypeError(`duplicate generic parameter "${parameter.name}"`);
      names.add(parameter.name);
    }
    if (parameters.length === 0)
      throw new OmpTypeError("generic declarations require at least one parameter");
  }
  function parseGenericParameters(source) {
    const trimmed = source.trim();
    const body = trimmed.startsWith("<") && trimmed.endsWith(">") ? trimmed.slice(1, -1) : trimmed;
    const parts = [];
    let start = 0;
    let depth = 0;
    let quote = "";
    for (let index = 0;index < body.length; index++) {
      const char = body[index];
      if (quote !== "") {
        if (char === quote && body[index - 1] !== "\\")
          quote = "";
        continue;
      }
      if (char === "'" || char === '"' || char === "`")
        quote = char;
      else if (char === "<" || char === "(" || char === "[")
        depth++;
      else if (char === ">" || char === ")" || char === "]")
        depth = Math.max(0, depth - 1);
      else if (char === "," && depth === 0) {
        parts.push(body.slice(start, index).trim());
        start = index + 1;
      }
    }
    parts.push(body.slice(start).trim());
    const parameters = parts.map((part) => {
      const constrained = part.match(/^([A-Za-z_$]\w*)\s+extends\s+(.+)$/s);
      return constrained === null ? { name: part } : { name: constrained[1], constraintDef: constrained[2].trim() };
    });
    validateGenericParameters(parameters);
    return parameters;
  }
  function parseGenericDeclaration(source) {
    const match = source.trim().match(/^([A-Za-z_$]\w*)\s*(<.*>)$/s);
    if (match === null)
      return;
    return { name: match[1], parameters: parseGenericParameters(match[2]) };
  }
  function isRuntimeGeneric(value) {
    return typeof value === "function" && GENERIC_META in value;
  }
  function genericResolver(parameters, arguments_, outer) {
    const byName = new Map;
    for (let index = 0;index < parameters.length; index++)
      byName.set(parameters[index].name, arguments_[index]);
    const resolve = (name) => byName.get(name) ?? outer?.(name);
    resolve.hasGeneric = outer?.hasGeneric;
    resolve.generic = outer?.generic;
    return resolve;
  }
  function parseGenericArgument(definition, outer) {
    if (outer === undefined) {
      try {
        return parseDef(definition);
      } catch (error) {
        if (!(error instanceof OmpTypeError) || !error.message.includes('unknown keyword "this"'))
          throw error;
      }
    }
    const root = {};
    const self2 = {
      k: "alias",
      name: "this",
      resolve: () => {
        if (root.current === undefined || root.current === self2)
          throw new OmpTypeError('"this" cannot be used as a root definition');
        return root.current;
      }
    };
    const resolve = (name) => name === "this" ? self2 : outer?.(name);
    if (outer !== undefined) {
      resolve.hasGeneric = outer.hasGeneric;
      resolve.generic = outer.generic;
    } else {
      markThisOnlyResolver(resolve);
    }
    root.current = parseDef(definition, resolve);
    if (root.current === self2)
      throw new OmpTypeError('"this" cannot be used as a root definition');
    return root.current;
  }
  function genericBodyIR(parameters, definition, arguments_, outer) {
    const resolve = genericResolver(parameters, arguments_, outer);
    const body = typeof definition === "function" && !(IR_BRAND in definition) ? definition(Object.fromEntries(parameters.map((parameter, index) => [
      parameter.name,
      makeType(arguments_[index], EMPTY_STEPS, EMPTY_META)
    ]))) : definition;
    return parseDef(body, resolve);
  }
  function createRuntimeGeneric(parameters, definition, outer, validateBody = true) {
    const constraintResolve = (name) => outer?.(name);
    constraintResolve.hasGeneric = outer?.hasGeneric;
    constraintResolve.generic = outer?.generic;
    validateGenericParameters(parameters);
    const placeholders = parameters.map((parameter) => parameter.constraintDef === undefined ? { k: "unknown" } : parseDef(parameter.constraintDef, constraintResolve));
    if (validateBody)
      genericBodyIR(parameters, definition, placeholders, outer);
    const meta = {
      parameters,
      instantiateIR(arguments_) {
        if (arguments_.length !== parameters.length) {
          throw new OmpTypeError(`generic expects ${parameters.length} arguments (received ${arguments_.length})`);
        }
        for (let index = 0;index < parameters.length; index++) {
          const parameter = parameters[index];
          if (parameter.constraintDef === undefined)
            continue;
          const constraint = parseDef(parameter.constraintDef, constraintResolve);
          if (!isSubtype(arguments_[index], constraint)) {
            throw new OmpTypeError(`${parameter.name} must be assignable to its constraint`);
          }
        }
        return genericBodyIR(parameters, definition, arguments_, outer);
      }
    };
    const generic = Object.assign((...arguments_) => makeType(meta.instantiateIR(arguments_.map((argument) => parseGenericArgument(argument, outer))), EMPTY_STEPS, EMPTY_META), { [GENERIC_META]: meta });
    Object.defineProperty(generic, GENERIC_META, { value: meta });
    return generic;
  }
  function type(first) {
    const count = arguments.length;
    if (count === 2 && typeof first === "string" && first.trimStart().startsWith("<")) {
      return createRuntimeGeneric(parseGenericParameters(first), arguments[1]);
    }
    let definition = first;
    if (count !== 1) {
      const expression = new Array(count);
      for (let index = 0;index < count; index++) {
        expression[index] = arguments[index];
      }
      definition = expression;
    }
    return makeType(parseGenericArgument(definition), EMPTY_STEPS, EMPTY_META);
  }
  function keywordSchema(name) {
    const ir = keywordIR(name);
    if (ir === undefined)
      throw new OmpTypeError(`missing built-in keyword ${name}`);
    return makeType(ir, [], {});
  }
  function parsedKeyword(name) {
    return Object.assign(keywordSchema(name), {
      parse: keywordSchema(`${name}.parse`)
    });
  }
  function preformattedKeyword(name) {
    return Object.assign(keywordSchema(name), {
      preformatted: keywordSchema(`${name}.preformatted`)
    });
  }
  function caseResolver(value) {
    if (typeof value !== "function")
      throw new OmpTypeError("match case values must be functions");
    return (input, ...args) => Reflect.apply(value, undefined, [input, ...args]);
  }
  function unionIR(branches) {
    const members = branches.map((branch) => branch.schema.ir);
    if (members.length === 0)
      return { k: "never" };
    if (members.length === 1)
      return members[0];
    return { k: "union", members };
  }
  function publicMatcher(state, fallback) {
    const fallbackResolver = typeof fallback === "function" ? caseResolver(fallback) : undefined;
    const casesIR = unionIR(state.branches);
    let casesSchema;
    if (state.key === undefined || state.branches.length === 0) {
      casesSchema = state.key === undefined ? makeType(casesIR, EMPTY_STEPS, EMPTY_META) : state.parse({ [state.key]: "never" });
    } else {
      const first = state.branches[0].schema.ir;
      if (first.k !== "object")
        throw new OmpTypeError("match.at cases must define object schemas");
      const propertyKey = String(state.key);
      const values = [];
      for (const branch of state.branches) {
        if (branch.schema.ir.k !== "object")
          throw new OmpTypeError("match.at cases must define object schemas");
        const property = branch.schema.ir.props.find((candidate) => candidate.key === propertyKey);
        if (property === undefined)
          throw new OmpTypeError(`match.at case is missing ${propertyKey}`);
        values.push(property.val);
      }
      const value = values.length === 1 ? values[0] : { k: "union", members: values };
      casesSchema = makeType({
        ...first,
        props: first.props.map((property) => property.key === propertyKey ? { ...property, val: value } : property)
      }, EMPTY_STEPS, EMPTY_META);
    }
    const execute = (input, args) => {
      let matchedInput = input;
      if (state.input !== undefined) {
        const validated = state.input.run(input);
        if (validated instanceof OmpErrors)
          return validated;
        matchedInput = validated;
      }
      for (const branch of state.branches) {
        const matched = branch.schema.run(matchedInput);
        if (!(matched instanceof OmpErrors))
          return branch.resolve(matched, ...args);
      }
      if (fallbackResolver !== undefined)
        return fallbackResolver(matchedInput, ...args);
      return casesSchema.run(matchedInput);
    };
    const schema = makeType({ k: "unknown" }, [{ kind: "pipe", fn: (input) => execute(input, []) }], EMPTY_META);
    const callable = (value, ...args) => {
      const result = execute(value, args);
      if ((fallback === "assert" || fallback === "never") && result instanceof OmpErrors) {
        throw new TraversalError(result);
      }
      return result;
    };
    Object.assign(callable, schema);
    Object.setPrototypeOf(callable, typeMethods);
    return callable;
  }
  function addMatchCases(state, cases) {
    const branches = [...state.branches];
    let fallback;
    for (const rawDefinition of Reflect.ownKeys(cases)) {
      const value = Reflect.get(cases, rawDefinition);
      if (rawDefinition === "default") {
        if (value !== "assert" && value !== "never" && value !== "reject" && typeof value !== "function") {
          throw new OmpTypeError('match default must be "assert", "never", "reject" or a function');
        }
        fallback = value;
        continue;
      }
      const definition = typeof rawDefinition === "symbol" ? rawDefinition : String(rawDefinition);
      const caseDefinition = state.key === undefined ? definition : { [state.key]: definition };
      branches.push({
        definition,
        schema: state.parse(caseDefinition),
        resolve: caseResolver(value)
      });
    }
    const next = { ...state, branches };
    return fallback === undefined ? createMatchParser(next) : publicMatcher(next, fallback);
  }
  function createMatchParser(state) {
    const parser = (cases) => addMatchCases(state, cases);
    parser.case = (definition, resolver) => {
      const caseDefinition = state.key === undefined ? definition : { [state.key]: definition };
      return createMatchParser({
        ...state,
        branches: [
          ...state.branches,
          {
            definition,
            schema: state.parse(caseDefinition),
            resolve: caseResolver(resolver)
          }
        ]
      });
    };
    parser.match = (cases) => addMatchCases(state, cases);
    parser.default = (fallback) => publicMatcher(state, fallback);
    function at(key, cases) {
      if (state.key !== undefined)
        throw new OmpTypeError("match.at may only be specified once");
      const next = createMatchParser({ ...state, key });
      return cases === undefined ? next : next.match(cases);
    }
    parser.at = at;
    parser.strings = (cases) => {
      if (state.key === undefined)
        throw new OmpTypeError("match.strings requires match.at(key)");
      const definitions = {};
      for (const key of Reflect.ownKeys(cases)) {
        definitions[key === "default" ? key : JSON.stringify(String(key))] = Reflect.get(cases, key);
      }
      return addMatchCases(state, definitions);
    };
    parser.in = (...args) => {
      if (state.input !== undefined)
        throw new OmpTypeError("match.in may only be specified once");
      return createMatchParser({
        ...state,
        ...args.length === 0 ? {} : { input: state.parse(args[0]) }
      });
    };
    return parser;
  }
  var matchBuilder = createMatchParser({
    parse: (definition) => type.raw(definition),
    branches: []
  });
  function fnExpression(ir) {
    switch (ir.k) {
      case "unknown":
      case "null":
      case "undefined":
      case "boolean":
      case "bigint":
      case "symbol":
      case "never":
      case "string":
      case "number":
        return ir.k;
      case "anyobject":
        return "object";
      case "lit":
        return typeof ir.v === "string" ? JSON.stringify(ir.v) : String(ir.v);
      case "union":
        return ir.members.map(fnExpression).join(" | ");
      case "intersection":
        return ir.members.map(fnExpression).join(" & ");
      case "array": {
        const element = fnExpression(ir.el);
        return ir.el.k === "unknown" ? "Array" : `${element.includes(" | ") ? `(${element})` : element}[]`;
      }
      case "tuple": {
        const elements = ir.prefix.map((item) => {
          const expression = fnExpression(item.val);
          if (item.hasDefault)
            return `${expression} = ${String(item.def)}`;
          return item.opt ? `${expression}?` : expression;
        });
        if (ir.variadic !== undefined)
          elements.push(`...${fnExpression({ k: "array", el: ir.variadic })}`);
        elements.push(...ir.postfix.map(fnExpression));
        return `[${elements.join(", ")}]`;
      }
      case "object":
        return `{ ${ir.props.map((property) => `${String(property.key)}${property.opt ? "?" : ""}: ${fnExpression(property.val)}`).join(", ")} }`;
      case "refine":
        return fnExpression(ir.base);
      case "morph":
        return `(In: ${fnExpression(ir.input)}) => To<${fnExpression(ir.out ?? { k: "unknown" })}>`;
      case "instance":
        return ir.ctor.name || "object";
      case "alias":
        return fnExpression(ir.resolve());
      case "sub": {
        const schema = ir.schema;
        if (!schema.hasSteps)
          return fnExpression(schema.ir);
        return `(In: ${fnExpression(schema.ir)}) => To<${fnExpression(schema.stepOut ?? { k: "unknown" })}>`;
      }
    }
  }
  function normalizeFnParameter(definition) {
    if (typeof definition !== "string")
      return definition;
    const optional = definition.match(/^(.*[^\s])\?$/);
    if (optional)
      return [optional[1], "?"];
    const defaulted = definition.match(/^(.*?)\s*=\s*(.+)$/);
    if (defaulted) {
      const source = defaulted[2];
      const value = source === "true" ? true : source === "false" ? false : source === "null" ? null : Number.isNaN(Number(source)) ? source : Number(source);
      return [defaulted[1], "=", value];
    }
    return definition;
  }
  function makeFn(resolve) {
    function parser(...definitions) {
      const marker = definitions.indexOf(":");
      if (marker !== -1 && (marker !== definitions.length - 2 || definitions.lastIndexOf(":") !== marker)) {
        throw new OmpTypeError(`":" must be followed by exactly one return type e.g:
fn("string", ":", "number")(s => s.length)`);
      }
      const spreadIndexes = [];
      for (let index = 0;index < definitions.length; index++) {
        if (definitions[index] === "...")
          spreadIndexes.push(index);
      }
      if (spreadIndexes.length > 1) {
        const secondSpread = definitions[spreadIndexes[1] + 1];
        if (Array.isArray(secondSpread) && secondSpread.some((element) => typeof element === "string" && (element.endsWith("?") || element.includes("=")))) {
          throw new OmpTypeError("An optional element may not follow a variadic element");
        }
        throw new OmpTypeError("A tuple may have at most one variadic element");
      }
      if (spreadIndexes.length === 1 && spreadIndexes[0] + 2 < (marker === -1 ? definitions.length : marker)) {
        const preceding = definitions.slice(0, spreadIndexes[0]);
        if (preceding.some((element) => typeof element === "string" && (element.endsWith("?") || /\s=\s/.test(element)))) {
          throw new OmpTypeError("A postfix required element cannot follow an optional or defaultable element");
        }
      }
      const parameterDefinitions = (marker === -1 ? definitions : definitions.slice(0, marker)).map(normalizeFnParameter);
      const params = makeType(parseDef(parameterDefinitions, resolve), [], {});
      const returns = marker === -1 ? makeType({ k: "unknown" }, [], {}) : makeType(parseDef(definitions[marker + 1], resolve), [], {});
      const parameterExpression = fnExpression(params.ir);
      const returnsExpression = fnExpression(returns.ir);
      return (implementation) => {
        if (typeof implementation !== "function")
          throw new OmpTypeError("type.fn requires a function implementation");
        const raw = (...arguments_) => {
          const validatedArguments = params.assert(arguments_);
          const result = Reflect.apply(implementation, undefined, validatedArguments);
          return returns.assert(result);
        };
        const typed = raw.bind(undefined);
        Object.defineProperties(typed, {
          name: { value: `bound typed ${implementation.name}`, configurable: true },
          raw: { value: implementation, enumerable: true },
          params: { value: params, enumerable: true },
          returns: { value: returns, enumerable: true },
          expression: {
            value: `(${parameterExpression.slice(1, -1)}) => ${returnsExpression}`,
            enumerable: true
          }
        });
        return typed;
      };
    }
    return Object.assign(parser, { raw: parser });
  }
  function isTypeValue(value) {
    return (typeof value === "function" || typeof value === "object" && value !== null) && IR_BRAND in value;
  }
  function resolveAlias(ir) {
    const seen = new Set;
    let current = ir;
    while (current.k === "alias" && !seen.has(current)) {
      seen.add(current);
      current = current.resolve();
    }
    return current;
  }
  function sameUnionMember(left, right) {
    const a = resolveAlias(left);
    const b = resolveAlias(right);
    if (a.k === "lit" && b.k === "lit")
      return Object.is(a.v, b.v);
    if (a.k !== b.k)
      return false;
    switch (a.k) {
      case "unknown":
      case "never":
      case "null":
      case "undefined":
      case "boolean":
      case "bigint":
      case "symbol":
      case "anyobject":
        return true;
      default:
        return false;
    }
  }
  function buildOr(definitions, resolve) {
    const members = [];
    const add = (candidate) => {
      const resolved = resolveAlias(candidate);
      if (resolved.k === "unknown") {
        members.length = 0;
        members.push(resolved);
        return false;
      }
      if (resolved.k === "never")
        return true;
      if (resolved.k === "union") {
        for (const member of resolved.members) {
          if (!add(member))
            return false;
        }
        return true;
      }
      if (!members.some((member) => sameUnionMember(member, candidate)))
        members.push(candidate);
      return true;
    };
    for (const definition of definitions) {
      if (!add(parseDef(definition, resolve)))
        break;
    }
    const ir = members.length === 0 ? { k: "never" } : members.length === 1 ? members[0] : { k: "union", members };
    return makeType(ir, [], {});
  }
  function buildAnd(definitions, resolve) {
    if (definitions.length === 0)
      return makeType({ k: "unknown" }, [], {});
    let ir = parseDef(definitions[0], resolve);
    for (let index = 1;index < definitions.length; index++) {
      ir = intersect(ir, parseDef(definitions[index], resolve));
    }
    return makeType(ir, [], {});
  }
  function requireNaryObject(ir) {
    const resolved = resolveAlias(ir);
    if (resolved.k !== "object")
      throw new OmpTypeError("merge requires an object schema");
    return resolved;
  }
  function buildMerge(definitions, resolve) {
    if (definitions.length === 0)
      return makeType({ k: "anyobject" }, [], {});
    let object = requireNaryObject(parseDef(definitions[0], resolve));
    for (let index = 1;index < definitions.length; index++) {
      object = mergeObjects(object, requireNaryObject(parseDef(definitions[index], resolve)));
    }
    return makeType(object, [], {});
  }
  function buildPipe(definitions, resolve) {
    if (definitions.length === 0)
      return makeType({ k: "unknown" }, [], {});
    const first = definitions[0];
    let schema = typeof first === "function" && !isTypeValue(first) ? appendPipes(makeType({ k: "unknown" }, [], {}), [first], false, true) : isTypeValue(first) ? first : makeType(parseDef(first, resolve), [], {});
    for (let index = 1;index < definitions.length; index++) {
      const definition = definitions[index];
      const pipe = typeof definition === "function" && !isTypeValue(definition) ? definition : isTypeValue(definition) ? definition : makeType(parseDef(definition, resolve), [], {});
      schema = appendPipes(schema, [pipe], false, true);
    }
    return schema;
  }
  function naryStatics(resolve) {
    return {
      or: (...definitions) => buildOr(definitions, resolve),
      and: (...definitions) => buildAnd(definitions, resolve),
      merge: (...definitions) => buildMerge(definitions, resolve),
      pipe: (...definitions) => buildPipe(definitions, resolve)
    };
  }
  ((type2) => {
    type2.errors = OmpErrors;
    function or(...definitions) {
      return buildOr(definitions);
    }
    type2.or = or;
    function array(definition) {
      return type(definition).array();
    }
    type2.array = array;
    function union(definitions) {
      return buildOr(definitions);
    }
    type2.union = union;
    function tuple(definitions) {
      return type(definitions);
    }
    type2.tuple = tuple;
    function record(key, value) {
      return type2.keywords.Record(key, value);
    }
    type2.record = record;
    function and(...definitions) {
      return buildAnd(definitions);
    }
    type2.and = and;
    function merge(...definitions) {
      return buildMerge(definitions);
    }
    type2.merge = merge;
    function pipe(...definitions) {
      return buildPipe(definitions);
    }
    type2.pipe = pipe;
    const normalize = Object.assign(keywordSchema("string.normalize"), {
      preformatted: keywordSchema("string.normalize.NFC.preformatted"),
      NFC: preformattedKeyword("string.normalize.NFC"),
      NFD: preformattedKeyword("string.normalize.NFD"),
      NFKC: preformattedKeyword("string.normalize.NFKC"),
      NFKD: preformattedKeyword("string.normalize.NFKD")
    });
    const base64 = Object.assign(keywordSchema("string.base64"), {
      url: keywordSchema("string.base64.url")
    });
    const date = Object.assign(parsedKeyword("string.date"), {
      iso: parsedKeyword("string.date.iso"),
      epoch: parsedKeyword("string.date.epoch")
    });
    const ip = Object.assign(keywordSchema("string.ip"), {
      v4: keywordSchema("string.ip.v4"),
      v6: keywordSchema("string.ip.v6")
    });
    const uuid = Object.assign(keywordSchema("string.uuid"), {
      v1: keywordSchema("string.uuid.v1"),
      v2: keywordSchema("string.uuid.v2"),
      v3: keywordSchema("string.uuid.v3"),
      v4: keywordSchema("string.uuid.v4"),
      v5: keywordSchema("string.uuid.v5"),
      v6: keywordSchema("string.uuid.v6"),
      v7: keywordSchema("string.uuid.v7"),
      v8: keywordSchema("string.uuid.v8")
    });
    type2.string = Object.defineProperties(makeType({ k: "string" }, [], {}), Object.getOwnPropertyDescriptors({
      alpha: keywordSchema("string.alpha"),
      alphanumeric: keywordSchema("string.alphanumeric"),
      base64,
      capitalize: preformattedKeyword("string.capitalize"),
      creditCard: keywordSchema("string.creditCard"),
      date,
      digits: keywordSchema("string.digits"),
      email: keywordSchema("string.email"),
      hex: keywordSchema("string.hex"),
      integer: parsedKeyword("string.integer"),
      ip,
      json: parsedKeyword("string.json"),
      lower: preformattedKeyword("string.lower"),
      normalize,
      numeric: parsedKeyword("string.numeric"),
      regex: keywordSchema("string.regex"),
      semver: keywordSchema("string.semver"),
      trim: preformattedKeyword("string.trim"),
      upper: preformattedKeyword("string.upper"),
      url: parsedKeyword("string.url"),
      uuid
    }));
    type2.parse = {
      number: keywordSchema("parse.number"),
      integer: keywordSchema("parse.integer"),
      json: keywordSchema("parse.json"),
      date: keywordSchema("parse.date"),
      url: keywordSchema("parse.url"),
      boolean: keywordSchema("parse.boolean"),
      bigint: keywordSchema("parse.bigint")
    };
    type2.number = Object.assign(makeType({ k: "number" }, [], {}), {
      integer: makeType({ k: "number", int: true }, [], {})
    });
    type2.arrayIndex = makeType({
      k: "refine",
      base: { k: "string" },
      pred: (value) => typeof value === "string" && /^(?:0|[1-9]\d*)$/.test(value),
      expected: "a non-negative integer string"
    }, [], {});
    type2.boolean = makeType({ k: "boolean" }, [], {});
    type2.bigint = makeType({ k: "bigint" }, [], {});
    type2.symbol = makeType({ k: "symbol" }, [], {});
    type2.object = makeType({ k: "anyobject" }, [], {});
    type2.unknown = makeType({ k: "unknown" }, [], {});
    type2.any = type2.unknown;
    type2.never = makeType({ k: "never" }, [], {});
    type2.keywords = {
      number: { integer: type2.number.integer },
      Map: keywordSchema("Map"),
      Set: keywordSchema("Set"),
      RegExp: keywordSchema("RegExp"),
      File: keywordSchema("File"),
      Error: keywordSchema("Error"),
      Function: keywordSchema("Function"),
      Array: {
        liftFrom(definition) {
          const element = parseDef(definition);
          const array = { k: "array", el: element, desc: "an object" };
          return makeType({
            k: "morph",
            input: { k: "union", members: [element, array] },
            fn: (value) => globalThis.Array.isArray(value) ? value : [value],
            out: array
          }, [], {});
        }
      },
      Record(key, value) {
        const keyIR = parseDef(key);
        if (keyIR.k !== "string" && keyIR.k !== "symbol") {
          throw new OmpTypeError("Record key must be assignable to string or symbol");
        }
        const valueIR = parseDef(value);
        const ir = keyIR.k === "symbol" ? { k: "object", props: [], symbolIndex: valueIR, extras: "keep" } : { k: "object", props: [], index: valueIR, extras: "keep" };
        return makeType(ir, [], {});
      },
      Partial(definition) {
        return makeType(setObjectOptionality(parseDef(definition), true, "partial"), [], {});
      },
      Required(definition) {
        return makeType(setObjectOptionality(parseDef(definition), false, "required"), [], {});
      },
      Pick(definition, ...keys) {
        return makeType(selectObjectProps(parseDef(definition), keys, true, "pick"), [], {});
      },
      Omit(definition, ...keys) {
        return makeType(selectObjectProps(parseDef(definition), keys, false, "omit"), [], {});
      },
      Merge(left, right) {
        return makeType(mergeObjectDefinition(parseDef(left), right), [], {});
      },
      object: {
        json: Object.defineProperties(keywordSchema("object.json"), {
          stringify: {
            value: keywordSchema("object.json.stringify"),
            enumerable: true
          }
        })
      },
      unknown: { any: keywordSchema("unknown.any") }
    };
    type2.Date = makeType({ k: "instance", ctor: globalThis.Date, expected: "a Date" }, [], {});
    function instanceOf(ctor) {
      if (typeof ctor !== "function" || ctor.prototype === undefined) {
        throw new OmpTypeError("instanceof operands must be constructors");
      }
      const name = Reflect.get(ctor, "name");
      const expected = ctor.prototype === Error.prototype ? "an Error" : typeof name === "string" && name.length > 0 ? `an instance of ${name}` : "an instance";
      return makeType({ k: "instance", ctor, expected }, [], {});
    }
    type2.instanceOf = instanceOf;
    function unit(value) {
      return makeType({ k: "lit", v: value }, [], {});
    }
    type2.unit = unit;
    function enumerated(...values) {
      const members = values.map((value) => ({ k: "lit", v: value }));
      const ir = members.length === 0 ? { k: "never" } : members.length === 1 ? members[0] : { k: "union", members };
      return makeType(ir, [], {});
    }
    type2.enumerated = enumerated;
    function enumeration(values) {
      return enumerated(...values);
    }
    type2.enumeration = enumeration;
    function valueOf(values) {
      const members = [];
      for (const key in values) {
        if (/^(?:0|[1-9]\d*)$/.test(key))
          continue;
        members.push({ k: "lit", v: values[key] });
      }
      const ir = members.length === 0 ? { k: "never" } : members.length === 1 ? members[0] : { k: "union", members };
      return makeType(ir, [], {});
    }
    type2.valueOf = valueOf;
    type2.match = matchBuilder;
    function define(definition) {
      return definition;
    }
    type2.define = define;
    type2.fn = makeFn();
    type2.declare = () => ({
      type: (definition) => type(definition)
    });
    function scope(aliases, options) {
      return buildScope(aliases, options);
    }
    type2.scope = scope;
    function module(definitions, options) {
      return scope(definitions, options).export();
    }
    type2.module = module;
    function generic(...arguments_) {
      if (arguments_.length === 2 && typeof arguments_[0] === "string" && arguments_[0].trimStart().startsWith("<")) {
        return createRuntimeGeneric(parseGenericParameters(arguments_[0]), arguments_[1]);
      }
      const parameters = arguments_.map((parameter) => {
        if (typeof parameter === "string")
          return { name: parameter.trim() };
        if (Array.isArray(parameter) && typeof parameter[0] === "string") {
          return { name: parameter[0].trim(), constraintDef: parameter[1] };
        }
        throw new OmpTypeError("generic parameters must be names or [name, constraint] pairs");
      });
      validateGenericParameters(parameters);
      return (definition) => createRuntimeGeneric(parameters, definition);
    }
    type2.generic = generic;
    function raw(def) {
      return makeType(parseDef(def), [], {});
    }
    type2.raw = raw;
    function withJsonSchema(schema, json) {
      const internal = schema;
      if (internal.hasDefault || hasMorph(internal.ir) || internal[kSteps].some((step) => step.kind === "pipe")) {
        throw new OmpTypeError("type.withJsonSchema cannot wrap schemas with defaults or output-changing morphs");
      }
      return makeType({
        k: "refine",
        base: { k: "unknown" },
        pred: (value) => {
          const result = schema(value);
          return result instanceof OmpErrors ? result : true;
        },
        expected: schema.expression,
        json: { ...json }
      }, [], {});
    }
    type2.withJsonSchema = withJsonSchema;
  })(type ||= {});
  Object.assign(type, {
    null: makeType({ k: "null" }, [], {}),
    undefined: makeType({ k: "undefined" }, [], {}),
    true: makeType({ k: "lit", v: true }, [], {}),
    false: makeType({ k: "lit", v: false }, [], {})
  });
  var MODULE_SCOPE = Symbol("omptype.moduleScope");
  function scope(aliases, options) {
    return buildScope(aliases, options);
  }
  ((scope) => {
    function define(definitions) {
      return definitions;
    }
    scope.define = define;
  })(scope ||= {});
  function isRuntimeModule(value) {
    return typeof value === "object" && value !== null && MODULE_SCOPE in value;
  }
  function buildScope(aliases, options) {
    const scopeMeta = options?.clone === undefined ? EMPTY_META : { clone: options.clone };
    const withScopeConfig = (ir) => options?.divisor === undefined ? ir : configureSelected(ir, options.divisor, { kind: "divisor" });
    const entries = new Map;
    for (const sourceName in aliases) {
      const isPrivate = sourceName.startsWith("#");
      const visibleName = isPrivate ? sourceName.slice(1) : sourceName;
      const declaration = parseGenericDeclaration(visibleName);
      const external = isRuntimeGeneric(aliases[sourceName]) ? aliases[sourceName] : undefined;
      const name = declaration?.name ?? visibleName;
      if (entries.has(name))
        throw new OmpTypeError(`alias "${name}" is declared as both public and private`);
      entries.set(name, {
        name,
        sourceName,
        private: isPrivate,
        genericParameters: declaration?.parameters ?? external?.[GENERIC_META].parameters,
        definition: aliases[sourceName],
        generic: external,
        materialized: false
      });
    }
    const references = new Map;
    const targets = new Map;
    const scopeValue = {};
    const materialize = (entry) => {
      if (entry.materialized)
        return entry.definition;
      entry.materialized = true;
      if (entry.genericParameters === undefined && typeof entry.definition === "function" && !(IR_BRAND in entry.definition)) {
        entry.definition = Reflect.apply(entry.definition, undefined, []);
      }
      return entry.definition;
    };
    const moduleSchema = (module, parts) => {
      let current = module;
      for (const part of parts) {
        if (!isRuntimeModule(current))
          return;
        const next = current[part];
        if (next === undefined)
          return;
        current = next;
      }
      if (isRuntimeModule(current)) {
        const root = current.root;
        return root !== undefined && !isRuntimeModule(root) ? root : undefined;
      }
      return current;
    };
    const resolve = (path) => {
      const [name, ...parts] = path.split(".");
      const entry = entries.get(name);
      if (entry === undefined || entry.genericParameters !== undefined)
        return;
      const definition = materialize(entry);
      if (isRuntimeModule(definition)) {
        const schema = moduleSchema(definition, parts);
        return schema === undefined ? undefined : embed(schema);
      }
      if (parts.length !== 0)
        return;
      const existing = references.get(name);
      if (existing !== undefined)
        return existing;
      const reference = {
        k: "alias",
        name,
        resolve: () => {
          const target = targets.get(name);
          if (target !== undefined)
            return target;
          const parsed = parseDef(definition, resolve);
          targets.set(name, parsed);
          return parsed;
        }
      };
      references.set(name, reference);
      return reference;
    };
    const genericFor = (entry) => {
      if (entry.generic !== undefined)
        return entry.generic;
      const parameters = entry.genericParameters;
      if (parameters === undefined)
        throw new OmpTypeError(`alias "${entry.name}" is not generic`);
      entry.generic = createRuntimeGeneric(parameters, entry.definition, resolve, false);
      return entry.generic;
    };
    const genericInstantiations = new Map;
    resolve.hasGeneric = (name) => entries.get(name)?.genericParameters !== undefined;
    resolve.generic = (name, arguments_) => {
      const entry = entries.get(name);
      if (entry === undefined || entry.genericParameters === undefined)
        return;
      const key = `${name}<${arguments_.map(expectedOf).join(",")}>`;
      const existing = genericInstantiations.get(key);
      if (existing !== undefined)
        return existing;
      let target;
      const reference = {
        k: "alias",
        name: key,
        resolve: () => {
          target ??= genericFor(entry)[GENERIC_META].instantiateIR(arguments_);
          return target;
        }
      };
      genericInstantiations.set(key, reference);
      target = genericFor(entry)[GENERIC_META].instantiateIR(arguments_);
      return target;
    };
    const bind = (schema) => {
      Reflect.set(schema, "$", scopeValue.current);
      Reflect.set(schema, "resolver", resolve);
      return schema;
    };
    const parseScoped = (definition) => bind(makeType(withScopeConfig(parseDef(definition, resolve)), EMPTY_STEPS, scopeMeta));
    const scopedMatch = createMatchParser({
      parse: (definition) => parseScoped(definition),
      branches: []
    });
    const scoped = Object.assign((definition) => parseScoped(definition), type, {
      fn: makeFn(resolve),
      match: scopedMatch,
      ...naryStatics(resolve)
    });
    const targetFor = (name) => {
      const resolved = resolve(name);
      if (resolved === undefined)
        throw new OmpTypeError(`unknown alias "${name}"`);
      return resolved.k === "alias" ? resolved.resolve() : resolved;
    };
    const schemaFor = (name) => bind(makeType(withScopeConfig(targetFor(name)), EMPTY_STEPS, scopeMeta));
    const bindModule = (names) => {
      const module = {};
      Object.defineProperty(module, MODULE_SCOPE, { value: scopeValue.current });
      for (const name of names) {
        const entry = entries.get(name);
        if (entry === undefined)
          continue;
        if (entry.genericParameters !== undefined) {
          module[name] = genericFor(entry);
          continue;
        }
        const definition = materialize(entry);
        module[name] = isRuntimeModule(definition) ? definition : schemaFor(name);
      }
      return module;
    };
    scopeValue.current = {
      type: scoped,
      match: scopedMatch,
      define(definition) {
        return definition;
      },
      resolve(name) {
        return schemaFor(name);
      },
      import(...names) {
        const selected = names.length === 0 ? [...entries.values()].filter((entry) => !entry.private) : names.map((name) => {
          const entry = entries.get(name);
          if (entry === undefined)
            throw new OmpTypeError(`unknown alias "${name}"`);
          return entry;
        });
        const imported = {};
        for (const entry of selected) {
          imported[`#${entry.sourceName.startsWith("#") ? entry.sourceName.slice(1) : entry.sourceName}`] = entry.genericParameters === undefined ? schemaFor(entry.name) : genericFor(entry);
        }
        return imported;
      },
      export(...names) {
        const selected = names.length === 0 ? [...entries.values()].filter((entry) => !entry.private).map((entry) => entry.name) : names;
        for (const entry of entries.values()) {
          if (entry.genericParameters !== undefined)
            genericFor(entry);
          else if (!isRuntimeModule(materialize(entry)))
            targetFor(entry.name);
        }
        return bindModule(selected);
      },
      get json() {
        const json = {};
        const add = (prefix, module) => {
          for (const name of Object.keys(module)) {
            const value = module[name];
            const path = prefix === "" ? name : `${prefix}.${name}`;
            if (isRuntimeModule(value))
              add(path, value);
            else
              json[path] = Reflect.get(value, "json");
          }
        };
        add("", bindModule([...entries.values()].filter((entry) => !entry.private).map((entry) => entry.name)));
        return json;
      }
    };
    return scopeValue.current;
  }
  // ../build/upstream/oh-my-pi/packages/utils/src/type-guards.ts
  function isRecord(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
  }
  // ../build/upstream/oh-my-pi/packages/utils/src/json-lexer.ts
  var VALID_ESCAPE_CHAR = new Uint8Array(128);
  for (const ch of '"\\/bfnrtu')
    VALID_ESCAPE_CHAR[ch.charCodeAt(0)] = 1;

  // ../build/upstream/oh-my-pi/packages/utils/src/json-parse.ts
  var CONTROL_ESCAPES = (() => {
    const e = [];
    e[8] = "\\b";
    e[9] = "\\t";
    e[10] = "\\n";
    e[12] = "\\f";
    e[13] = "\\r";
    for (let cp = 0;cp <= 31; cp++) {
      e[cp] ??= `\\u${cp.toString(16).padStart(4, "0")}`;
    }
    return e;
  })();
  var INCOMPLETE = Symbol("incomplete");
  // ../build/upstream/oh-my-pi/packages/utils/src/lru.ts
  function positiveInteger(value, name) {
    if (value === undefined)
      return 0;
    if (!Number.isInteger(value) || value < 0)
      throw new TypeError(`${name} must be a non-negative integer`);
    return value;
  }

  class LRUCache {
    #entries = new Map;
    #max;
    #maxSize;
    #maxEntrySize;
    #sizeCalculation;
    #ttl;
    #updateAgeOnGet;
    #dispose;
    #calculatedSize = 0;
    constructor(options) {
      this.#max = positiveInteger(options.max, "max");
      this.#maxSize = positiveInteger(options.maxSize, "maxSize");
      const explicitMaxEntrySize = positiveInteger(options.maxEntrySize, "maxEntrySize");
      this.#maxEntrySize = explicitMaxEntrySize || this.#maxSize;
      this.#ttl = positiveInteger(options.ttl, "ttl");
      if (this.#max === 0 && this.#maxSize === 0 && this.#ttl === 0) {
        throw new TypeError("At least one of max, maxSize, or ttl is required");
      }
      if ((this.#maxSize !== 0 || this.#maxEntrySize !== 0) && options.sizeCalculation === undefined) {
        throw new TypeError("sizeCalculation is required when a size limit is set");
      }
      this.#sizeCalculation = options.sizeCalculation;
      this.#updateAgeOnGet = options.updateAgeOnGet === true;
      this.#dispose = options.dispose;
    }
    get size() {
      return this.#entries.size;
    }
    get calculatedSize() {
      return this.#calculatedSize;
    }
    set(key, value) {
      if (value === undefined) {
        this.delete(key);
        return this;
      }
      const size = this.#entrySize(value, key);
      const previous = this.#entries.get(key);
      if (this.#maxEntrySize !== 0 && size > this.#maxEntrySize) {
        if (previous !== undefined)
          this.#remove(key, previous, "set");
        return this;
      }
      if (previous !== undefined) {
        if (previous.value !== value)
          this.#dispose?.(previous.value, key, "set");
        this.#calculatedSize -= previous.size;
        this.#entries.delete(key);
      }
      while (this.#max !== 0 && this.#entries.size >= this.#max || this.#maxSize !== 0 && this.#calculatedSize + size > this.#maxSize) {
        const oldest = this.#entries.entries().next().value;
        if (oldest === undefined)
          break;
        this.#remove(oldest[0], oldest[1], "evict");
      }
      this.#entries.set(key, { value, size, start: this.#ttl === 0 ? 0 : performance.now() });
      this.#calculatedSize += size;
      return this;
    }
    get(key) {
      const entry = this.#entries.get(key);
      if (entry === undefined)
        return;
      if (this.#isStale(entry)) {
        this.#remove(key, entry, "expire");
        return;
      }
      if (this.#updateAgeOnGet && this.#ttl !== 0)
        entry.start = performance.now();
      this.#entries.delete(key);
      this.#entries.set(key, entry);
      return entry.value;
    }
    has(key) {
      const entry = this.#entries.get(key);
      return entry !== undefined && !this.#isStale(entry);
    }
    peek(key) {
      const entry = this.#entries.get(key);
      return entry === undefined || this.#isStale(entry) ? undefined : entry.value;
    }
    delete(key) {
      const entry = this.#entries.get(key);
      if (entry === undefined)
        return false;
      this.#remove(key, entry, "delete");
      return true;
    }
    clear() {
      for (const [key, entry] of this.#entries)
        this.#dispose?.(entry.value, key, "delete");
      this.#entries.clear();
      this.#calculatedSize = 0;
    }
    *keys() {
      const entries = [...this.#entries.entries()];
      for (let index = entries.length - 1;index >= 0; index--) {
        const [key, entry] = entries[index];
        if (!this.#isStale(entry))
          yield key;
      }
    }
    *values() {
      const entries = [...this.#entries.values()];
      for (let index = entries.length - 1;index >= 0; index--) {
        const entry = entries[index];
        if (!this.#isStale(entry))
          yield entry.value;
      }
    }
    #entrySize(value, key) {
      if (this.#sizeCalculation === undefined)
        return 0;
      const size = this.#sizeCalculation(value, key);
      if (!Number.isInteger(size) || size <= 0)
        throw new TypeError("sizeCalculation return invalid (expect positive integer)");
      return size;
    }
    #isStale(entry) {
      return this.#ttl !== 0 && performance.now() - entry.start > this.#ttl;
    }
    #remove(key, entry, reason) {
      this.#dispose?.(entry.value, key, reason);
      this.#entries.delete(key);
      this.#calculatedSize -= entry.size;
    }
  }

  // ../build/upstream/oh-my-pi/packages/utils/src/template.ts
  class SafeString {
    #value;
    constructor(value) {
      this.#value = String(value);
    }
    toString() {
      return this.#value;
    }
    toHTML() {
      return this.#value;
    }
  }
  var helpers = new Map;
  var partials = new Map;
  var BLOCK_TAG = /^\s*\{\{(?:#|\/|\^|else\b|!)/;
  function stripStandalone(source) {
    const lines = source.split(/(?<=\n)/);
    for (let index = 0;index < lines.length; index++) {
      const line = lines[index];
      const body = line.endsWith(`
`) ? line.slice(0, -1).replace(/\r$/, "") : line;
      if (/^\s*\{\{!--/.test(body) && !body.includes("--}}")) {
        for (let end = index + 1;end < lines.length; end++) {
          const endLine = lines[end].endsWith(`
`) ? lines[end].slice(0, -1).replace(/\r$/, "") : lines[end];
          const close = endLine.indexOf("--}}");
          if (close < 0)
            continue;
          if (/^\s*$/.test(endLine.slice(close + 4))) {
            for (let commentLine = index;commentLine <= end; commentLine++)
              lines[commentLine] = "";
            index = end;
          }
          break;
        }
        continue;
      }
      if (BLOCK_TAG.test(body) && /^\s*\{\{(?:#|\/|\^|else\b|!)[^{}]*\}\}\s*$/.test(body)) {
        lines[index] = body.trim();
      }
    }
    return lines.join("");
  }
  function tokenizeExpression(source) {
    const tokens = [];
    let start = -1;
    let quote = "";
    let depth = 0;
    let bracketDepth = 0;
    for (let index = 0;index < source.length; index++) {
      const char = source[index];
      if (quote) {
        if (char === "\\" && index + 1 < source.length)
          index++;
        else if (char === quote)
          quote = "";
        continue;
      }
      if (char === '"' || char === "'") {
        if (start < 0)
          start = index;
        quote = char;
        continue;
      }
      if (char === "(") {
        if (start < 0)
          start = index;
        depth++;
        continue;
      }
      if (char === ")") {
        depth--;
        continue;
      }
      if (char === "[") {
        if (start < 0)
          start = index;
        bracketDepth++;
        continue;
      }
      if (char === "]") {
        bracketDepth--;
        continue;
      }
      if (/\s/.test(char) && depth === 0 && bracketDepth === 0) {
        if (start >= 0)
          tokens.push(source.slice(start, index));
        start = -1;
      } else if (start < 0) {
        start = index;
      }
    }
    if (start >= 0)
      tokens.push(source.slice(start));
    return tokens;
  }
  function parseString(token) {
    const quote = token[0];
    let result = "";
    for (let index = 1;index < token.length - 1; index++) {
      const char = token[index];
      if (char === "\\" && index + 1 < token.length - 1) {
        const next = token[++index];
        result += next === quote || next === "\\" ? next : `\\${next}`;
      } else
        result += char;
    }
    return result;
  }
  function parseAtom(token) {
    if (token.startsWith("(") && token.endsWith(")"))
      return parseCall(token.slice(1, -1));
    if (token.startsWith('"') && token.endsWith('"') || token.startsWith("'") && token.endsWith("'")) {
      return { kind: "literal", value: parseString(token) };
    }
    if (token === "true" || token === "false")
      return { kind: "literal", value: token === "true" };
    if (token === "null")
      return { kind: "literal", value: null };
    if (token === "undefined")
      return { kind: "literal", value: undefined };
    if (/^-?(?:\d+\.?\d*|\.\d+)$/.test(token))
      return { kind: "literal", value: Number(token) };
    return { kind: "path", value: token };
  }
  function hashSeparator(token) {
    let quote = "";
    let depth = 0;
    for (let index = 0;index < token.length; index++) {
      const char = token[index];
      if (quote) {
        if (char === "\\")
          index++;
        else if (char === quote)
          quote = "";
      } else if (char === '"' || char === "'")
        quote = char;
      else if (char === "(")
        depth++;
      else if (char === ")")
        depth--;
      else if (char === "=" && depth === 0)
        return index;
    }
    return -1;
  }
  function parseCall(source) {
    const tokens = tokenizeExpression(source.trim());
    const name = tokens.shift() ?? "";
    const args = [];
    const hash = {};
    for (const token of tokens) {
      const separator = hashSeparator(token);
      if (separator > 0)
        hash[token.slice(0, separator)] = parseAtom(token.slice(separator + 1));
      else
        args.push(parseAtom(token));
    }
    return { kind: "call", name, args, hash };
  }
  function findTagEnd(source, start, triple) {
    const close = triple ? "}}}" : "}}";
    let quote = "";
    let depth = 0;
    for (let index = start;index <= source.length - close.length; index++) {
      const char = source[index];
      if (quote) {
        if (char === "\\")
          index++;
        else if (char === quote)
          quote = "";
        continue;
      }
      if (char === '"' || char === "'")
        quote = char;
      else if (char === "(")
        depth++;
      else if (char === ")")
        depth--;
      else if (depth === 0 && source.startsWith(close, index))
        return index;
    }
    throw new Error("Parse error: unclosed template expression");
  }
  function parseTemplate(source) {
    const root = [];
    const stack = [];
    let target = root;
    let cursor = 0;
    while (cursor < source.length) {
      const open = source.indexOf("{{", cursor);
      if (open < 0) {
        if (cursor < source.length)
          target.push({ kind: "text", value: source.slice(cursor) });
        break;
      }
      if (open > cursor)
        target.push({ kind: "text", value: source.slice(cursor, open) });
      if (source.startsWith("{{!--", open)) {
        const end = source.indexOf("--}}", open + 6);
        if (end < 0)
          throw new Error("Parse error: unclosed comment");
        cursor = end + 4;
        continue;
      }
      const triple = source.startsWith("{{{", open);
      const contentStart = open + (triple ? 3 : 2);
      const end = findTagEnd(source, contentStart, triple);
      const raw = source.slice(contentStart, end).trim();
      cursor = end + (triple ? 3 : 2);
      if (!raw || raw.startsWith("!"))
        continue;
      if (raw === "else" || raw.startsWith("else ")) {
        const current = stack[stack.length - 1];
        if (!current)
          throw new Error("Parse error: unexpected else");
        target = current.node.inverse;
        if (raw.length > 4) {
          const parentTarget = target;
          const nested = {
            kind: "block",
            expression: parseCall(raw.slice(5)),
            body: [],
            inverse: [],
            inverted: false
          };
          target.push(nested);
          target = nested.body;
          stack.push({ node: nested, target: parentTarget, inverted: false, chained: true });
        }
        continue;
      }
      if (raw.startsWith("#") || raw.startsWith("^")) {
        const inverted = raw.startsWith("^");
        const node = {
          kind: "block",
          expression: parseCall(raw.slice(1)),
          body: [],
          inverse: [],
          inverted
        };
        target.push(node);
        stack.push({ node, target, inverted, chained: false });
        target = node.body;
        continue;
      }
      if (raw.startsWith("/")) {
        let current = stack.pop();
        while (current?.chained)
          current = stack.pop();
        if (!current || current.node.expression.name !== raw.slice(1).trim())
          throw new Error(`Parse error: mismatched ${raw}`);
        if (current.inverted)
          [current.node.body, current.node.inverse] = [current.node.inverse, current.node.body];
        target = current.target;
        continue;
      }
      if (raw.startsWith(">"))
        target.push({ kind: "partial", expression: parseCall(raw.slice(1)) });
      else
        target.push({
          kind: "output",
          expression: parseCall(raw.startsWith("&") ? raw.slice(1) : raw),
          escaped: !triple && !raw.startsWith("&")
        });
    }
    if (stack.length)
      throw new Error(`Parse error: unclosed block ${stack[stack.length - 1].node.expression.name}`);
    return root;
  }
  function pathParts(path) {
    const parts = [];
    let start = 0;
    let bracketStart = -1;
    for (let index = 0;index <= path.length; index++) {
      const char = path[index];
      if (char === "[" && bracketStart < 0) {
        if (index > start)
          parts.push(path.slice(start, index).replace(/[./]+$/, ""));
        bracketStart = index + 1;
      } else if (char === "]" && bracketStart >= 0) {
        parts.push(path.slice(bracketStart, index));
        start = index + 1;
        bracketStart = -1;
      } else if ((char === "." || char === "/" || char === undefined) && bracketStart < 0) {
        if (index > start)
          parts.push(path.slice(start, index));
        start = index + 1;
      }
    }
    return parts.filter(Boolean);
  }
  function property(parent, key) {
    if (parent == null)
      return;
    if (key === "length" && (typeof parent === "string" || Array.isArray(parent)))
      return parent.length;
    if (typeof parent !== "object" && typeof parent !== "function")
      return;
    if (key === "__proto__" || key === "prototype" || key === "constructor")
      return;
    const record = parent;
    return Object.hasOwn(record, key) ? record[key] : undefined;
  }
  function resolvePath(path, frame) {
    if (path === "this" || path === ".")
      return frame.context;
    let current = frame;
    while (path.startsWith("../")) {
      current = current.parents[0] ?? current;
      path = path.slice(3);
    }
    if (path === "this" || path === ".")
      return current.context;
    if (path.startsWith("this."))
      path = path.slice(5);
    if (path === "@root")
      return current.root;
    if (path.startsWith("@root.")) {
      let value = current.root;
      for (const part of pathParts(path.slice(6)))
        value = property(value, part);
      return value;
    }
    if (path.startsWith("@")) {
      const parts = pathParts(path.slice(1));
      let value = current.data[parts.shift() ?? ""];
      for (const part of parts)
        value = property(value, part);
      return value;
    }
    let value = current.context;
    for (const part of pathParts(path))
      value = property(value, part);
    return typeof value === "function" ? value.call(current.context) : value;
  }
  function childFrame(frame, context, data = frame.data) {
    return { context, parents: [frame, ...frame.parents], root: frame.root, data };
  }
  function evaluateExpression(expression, frame, evaluation) {
    if (expression.kind === "literal")
      return expression.value;
    if (expression.kind === "path")
      return resolvePath(expression.value, frame);
    return evaluateCall(expression, frame, evaluation, false);
  }
  function isConditionalTruthy(value, includeZero = false) {
    return value === 0 ? includeZero : Boolean(value) && !(Array.isArray(value) && value.length === 0);
  }
  function renderNodes(nodes, frame, evaluation) {
    let result = "";
    for (const node of nodes) {
      if (node.kind === "text")
        result += node.value;
      else if (node.kind === "output") {
        const value = evaluateCall(node.expression, frame, evaluation, false);
        result += stringify(value, node.escaped && !evaluation.options.noEscape);
      } else if (node.kind === "partial")
        result += renderPartial(node, frame, evaluation);
      else
        result += evaluateBlock(node, frame, evaluation);
    }
    return result;
  }
  function helperOptions(name, hash, frame, evaluation, body = [], inverse = []) {
    return {
      name,
      hash,
      data: frame.data,
      fn: (context = frame.context, options) => renderNodes(body, childFrame(frame, context, options?.data ?? frame.data), evaluation),
      inverse: (context = frame.context, options) => renderNodes(inverse, childFrame(frame, context, options?.data ?? frame.data), evaluation),
      lookupProperty: property
    };
  }
  function evaluateHash(hash, frame, evaluation) {
    const result = {};
    for (const key in hash)
      result[key] = evaluateExpression(hash[key], frame, evaluation);
    return result;
  }
  function findHelper(name, evaluation) {
    return evaluation.runtime.helpers?.[name] ?? evaluation.helpers.get(name);
  }
  function evaluateCall(call, frame, evaluation, forceHelper, body = [], inverse = []) {
    const helper = findHelper(call.name, evaluation);
    const args = call.args.map((argument) => evaluateExpression(argument, frame, evaluation));
    const hash = evaluateHash(call.hash, frame, evaluation);
    if (helper)
      return helper.call(frame.context, ...args, helperOptions(call.name, hash, frame, evaluation, body, inverse));
    if (call.name === "lookup" && args.length >= 2)
      return property(args[0], String(args[1]));
    if (forceHelper || args.length)
      throw new Error(`Missing helper: "${call.name}"`);
    for (const _key in hash)
      throw new Error(`Missing helper: "${call.name}"`);
    return resolvePath(call.name, frame);
  }
  function evaluateBlock(node, frame, evaluation) {
    const { name } = node.expression;
    const helper = findHelper(name, evaluation);
    if (helper)
      return stringify(evaluateCall(node.expression, frame, evaluation, true, node.body, node.inverse), false);
    const args = node.expression.args.map((argument) => evaluateExpression(argument, frame, evaluation));
    const value = args.length ? args[0] : resolvePath(name, frame);
    const hash = evaluateHash(node.expression.hash, frame, evaluation);
    if (name === "if" || name === "unless") {
      const truthy = isConditionalTruthy(value, hash.includeZero === true);
      const branch = name === "if" ? truthy : !truthy;
      return renderNodes(branch ? node.body : node.inverse, frame, evaluation);
    }
    if (name === "each") {
      if (Array.isArray(value)) {
        if (!value.length)
          return renderNodes(node.inverse, frame, evaluation);
        return value.map((item, index) => renderNodes(node.body, childFrame(frame, item, {
          ...frame.data,
          index,
          key: index,
          first: index === 0,
          last: index === value.length - 1
        }), evaluation)).join("");
      }
      if (value && typeof value === "object") {
        const entries = Object.entries(value);
        if (!entries.length)
          return renderNodes(node.inverse, frame, evaluation);
        return entries.map(([key, item], index) => renderNodes(node.body, childFrame(frame, item, {
          ...frame.data,
          index,
          key,
          first: index === 0,
          last: index === entries.length - 1
        }), evaluation)).join("");
      }
      return renderNodes(node.inverse, frame, evaluation);
    }
    if (name === "with")
      return isConditionalTruthy(value) ? renderNodes(node.body, childFrame(frame, value), evaluation) : renderNodes(node.inverse, frame, evaluation);
    const resolved = resolvePath(name, frame);
    if (Array.isArray(resolved))
      return resolved.map((item) => renderNodes(node.body, childFrame(frame, item), evaluation)).join("") || renderNodes(node.inverse, frame, evaluation);
    return resolved === false || resolved == null ? renderNodes(node.inverse, frame, evaluation) : renderNodes(node.body, childFrame(frame, resolved), evaluation);
  }
  function renderPartial(node, frame, evaluation) {
    const partial = evaluation.runtime.partials?.[node.expression.name] ?? evaluation.partials.get(node.expression.name);
    if (partial === undefined)
      throw new Error(`The partial ${node.expression.name} could not be found`);
    const context = node.expression.args.length ? evaluateExpression(node.expression.args[0], frame, evaluation) : frame.context;
    const hash = evaluateHash(node.expression.hash, frame, evaluation);
    const merged = hash && context && typeof context === "object" ? { ...context, ...hash } : context;
    return typeof partial === "function" ? partial(merged, evaluation.runtime) : compile2(partial, evaluation.options)(merged, evaluation.runtime);
  }
  function stringify(value, shouldEscape) {
    if (value == null)
      return "";
    if (value instanceof SafeString)
      return value.toString();
    const text = String(value);
    return shouldEscape ? escapeExpression(text) : text;
  }
  function escapeExpression(value) {
    const text = value == null ? "" : String(value);
    return text.replace(/[&<>"'`=]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#x27;", "`": "&#x60;", "=": "&#x3D;" })[char] ?? char);
  }
  function compile2(source, options = {}) {
    const nodes = parseTemplate(stripStandalone(source));
    return (context, runtime = {}) => {
      const root = context ?? {};
      const frame = { context: root, parents: [], root, data: { root, ...runtime.data } };
      return renderNodes(nodes, frame, { helpers, partials, options, runtime });
    };
  }
  function create() {
    return new TemplateEngine;
  }

  class TemplateEngine {
    #helpers = new Map;
    #partials = new Map;
    registerHelper(name, helper) {
      this.#helpers.set(name, helper);
    }
    registerPartial(name, partial) {
      this.#partials.set(name, partial);
    }
    compile(source, options = {}) {
      const nodes = parseTemplate(stripStandalone(source));
      return (context, runtime = {}) => {
        const root = context ?? {};
        const frame = { context: root, parents: [], root, data: { root, ...runtime.data } };
        return renderNodes(nodes, frame, { helpers: this.#helpers, partials: this.#partials, options, runtime });
      };
    }
  }

  // ../build/upstream/oh-my-pi/packages/utils/src/prompt.ts
  var OPENING_XML = /^<([a-z_-]+)(?:\s+[^>]*)?>$/;
  function closingTagName(s) {
    const n = s.length;
    if (n < 4 || s.charCodeAt(n - 1) !== 62)
      return null;
    for (let j = 2;j < n - 1; j++) {
      const c = s.charCodeAt(j);
      if (!(c >= 97 && c <= 122 || c === 45 || c === 95))
        return null;
    }
    return s.slice(2, n - 1);
  }
  function openingTagName(s) {
    const n = s.length;
    if (n < 3 || s.charCodeAt(n - 1) !== 62)
      return null;
    let j = 1;
    while (j < n - 1) {
      const c = s.charCodeAt(j);
      if (c >= 97 && c <= 122 || c === 45 || c === 95)
        j++;
      else
        break;
    }
    if (j === 1)
      return null;
    if (j === n - 1)
      return s.slice(1, j);
    const c = s.charCodeAt(j);
    if (c !== 32 && c !== 9) {
      if (c < 128)
        return null;
      const match = OPENING_XML.exec(s);
      return match ? match[1] : null;
    }
    return s.indexOf(">", j + 1) === n - 1 ? s.slice(1, j) : null;
  }
  var TABLE_ROW = /^\|.*\|$/;
  var TABLE_SEP = /^\|[-:\s|]+\|$/;
  var NON_BLANK = /\S/;
  var RFC2119_BOLD = /\*\*(MUST NOT|SHOULD NOT|RECOMMENDED|REQUIRED|OPTIONAL|SHOULD|MUST|MAY|NEVER|AVOID)\*\*/g;
  var RFC2119_GUARD = /\*\*(?:MUST|SHOULD|RECOMMENDED|REQUIRED|OPTIONAL|MAY|NEVER|AVOID)|MUST NOT|SHOULD NOT/;
  var MUST_NOT = /\bMUST NOT\b/g;
  var SHOULD_NOT = /\bSHOULD NOT\b/g;
  function applyRfc2119(text) {
    return text.replace(RFC2119_BOLD, "$1").replace(MUST_NOT, "NEVER").replace(SHOULD_NOT, "AVOID");
  }
  function normalizeRfc2119(line) {
    if (!RFC2119_GUARD.test(line))
      return line;
    if (!line.includes("`"))
      return applyRfc2119(line);
    const segments = line.split("`");
    for (let i = 0;i < segments.length; i += 2) {
      segments[i] = applyRfc2119(segments[i]);
    }
    return segments.join("`");
  }
  function compactTableRow(line) {
    const cells = line.split("|");
    return cells.map((c) => c.trim()).join("|");
  }
  function compactTableSep(line) {
    const cells = line.split("|").filter((c) => c.trim());
    const normalized = cells.map((c) => {
      const trimmed = c.trim();
      const left = trimmed.startsWith(":");
      const right = trimmed.endsWith(":");
      if (left && right)
        return ":---:";
      if (left)
        return ":---";
      if (right)
        return "---:";
      return "---";
    });
    return `|${normalized.join("|")}|`;
  }
  var HTML_COMMENT_OPEN = "<!--";
  var HTML_COMMENT_CLOSE = "-->";
  var ASCII_SYMBOLS = /\.{3}|<->|->|<-|!=|<=|>=/g;
  var ASCII_SYMBOL_REPLACEMENTS = {
    "...": "…",
    "<->": "↔",
    "->": "→",
    "<-": "←",
    "!=": "≠",
    "<=": "≤",
    ">=": "≥"
  };
  var replaceAsciiSymbol = (match) => ASCII_SYMBOL_REPLACEMENTS[match];
  function replaceCommonAsciiSymbols(line) {
    return line.replace(ASCII_SYMBOLS, replaceAsciiSymbol);
  }
  function replaceCommonAsciiSymbolsOutsideHtmlComments(line, state) {
    if (!state.inHtmlComment && !line.includes(HTML_COMMENT_OPEN)) {
      return replaceCommonAsciiSymbols(line);
    }
    let result = "";
    let cursor = 0;
    while (cursor < line.length) {
      if (state.inHtmlComment) {
        const closeIndex = line.indexOf(HTML_COMMENT_CLOSE, cursor);
        if (closeIndex === -1) {
          return result + line.slice(cursor);
        }
        result += line.slice(cursor, closeIndex + HTML_COMMENT_CLOSE.length);
        cursor = closeIndex + HTML_COMMENT_CLOSE.length;
        state.inHtmlComment = false;
        continue;
      }
      const openIndex = line.indexOf(HTML_COMMENT_OPEN, cursor);
      if (openIndex === -1) {
        result += replaceCommonAsciiSymbols(line.slice(cursor));
        return result;
      }
      result += replaceCommonAsciiSymbols(line.slice(cursor, openIndex));
      const closeIndex = line.indexOf(HTML_COMMENT_CLOSE, openIndex + HTML_COMMENT_OPEN.length);
      if (closeIndex === -1) {
        result += line.slice(openIndex);
        state.inHtmlComment = true;
        return result;
      }
      result += line.slice(openIndex, closeIndex + HTML_COMMENT_CLOSE.length);
      cursor = closeIndex + HTML_COMMENT_CLOSE.length;
    }
    return result;
  }
  function format2(content, options = {}) {
    const {
      renderPhase = "post-render",
      replaceAsciiSymbols = false,
      normalizeRfc2119: shouldNormalizeRfc2119 = false
    } = options;
    const isPreRender = renderPhase === "pre-render";
    const lines = content.split(`
`);
    const result = new Array(lines.length);
    let n = 0;
    let inCodeBlock = false;
    const htmlCommentState = { inHtmlComment: false };
    const topLevelTags = [];
    for (let i = 0;i < lines.length; i++) {
      const raw = lines[i];
      const last = raw.charCodeAt(raw.length - 1);
      let line = last <= 32 || last >= 128 ? raw.trimEnd() : raw;
      let s = 0;
      let first = line.charCodeAt(0);
      while (first === 32 || first === 9)
        first = line.charCodeAt(++s);
      if (first >= 128) {
        s = line.length - line.trimStart().length;
        first = line.charCodeAt(s);
      }
      if ((first === 96 || first === 126) && (line.startsWith("```", s) || line.startsWith("~~~", s))) {
        inCodeBlock = !inCodeBlock;
        result[n++] = line;
        continue;
      }
      if (inCodeBlock) {
        result[n++] = line;
        continue;
      }
      if (replaceAsciiSymbols) {
        const replaced = replaceCommonAsciiSymbolsOutsideHtmlComments(line, htmlCommentState);
        if (replaced !== line) {
          line = replaced;
          s = 0;
          first = line.charCodeAt(0);
          while (first === 32 || first === 9)
            first = line.charCodeAt(++s);
          if (first >= 128) {
            s = line.length - line.trimStart().length;
            first = line.charCodeAt(s);
          }
        }
      }
      let isClosingLine = false;
      if (first === 60) {
        const trimmedStart = s === 0 ? line : line.slice(s);
        if (trimmedStart.charCodeAt(1) === 47) {
          const tagName = closingTagName(trimmedStart);
          if (tagName !== null) {
            isClosingLine = true;
            if (topLevelTags.length > 0 && topLevelTags[topLevelTags.length - 1] === tagName) {
              topLevelTags.pop();
            }
          }
        } else if (s === 0 && !trimmedStart.endsWith("/>")) {
          const tagName = openingTagName(trimmedStart);
          if (tagName !== null)
            topLevelTags.push(tagName);
        }
      } else if (first === 124) {
        const trimmedStart = s === 0 ? line : line.slice(s);
        if (TABLE_SEP.test(trimmedStart)) {
          line = `${line.slice(0, s)}${compactTableSep(trimmedStart)}`;
        } else if (TABLE_ROW.test(trimmedStart)) {
          line = `${line.slice(0, s)}${compactTableRow(trimmedStart)}`;
        }
      }
      if (shouldNormalizeRfc2119) {
        line = normalizeRfc2119(line);
      }
      if (s >= line.length) {
        const next = lines[i + 1];
        if (next === undefined || next.length === 0 || !NON_BLANK.test(next)) {
          while (n > 0 && result[n - 1].length === 0)
            n--;
          let j = i + 1;
          while (j < lines.length && (lines[j].length === 0 || !NON_BLANK.test(lines[j])))
            j++;
          i = j - 1;
          continue;
        }
        if (n === 0 || result[n - 1].length === 0) {
          continue;
        }
      }
      if (isClosingLine || isPreRender && first === 123 && line.startsWith("{{/", s)) {
        while (n > 0 && result[n - 1].length === 0)
          n--;
      }
      result[n++] = line;
    }
    while (n > 0 && result[n - 1].length === 0)
      n--;
    result.length = n;
    return result.join(`
`);
  }
  var handlebars = create();
  handlebars.registerHelper("arg", function(index) {
    const args = this.args ?? [];
    const parsedIndex = typeof index === "number" ? index : Number.parseInt(index, 10);
    if (!Number.isFinite(parsedIndex))
      return "";
    const zeroBased = parsedIndex - 1;
    if (zeroBased < 0)
      return "";
    return args[zeroBased] ?? "";
  });
  handlebars.registerHelper("list", function(context, options) {
    if (!Array.isArray(context) || context.length === 0)
      return "";
    const prefix = options.hash.prefix ?? "";
    const suffix = options.hash.suffix ?? "";
    const rawSeparator = options.hash.join ?? `
`;
    const separator = rawSeparator.replace(/\\n/g, `
`).replace(/\\t/g, "\t");
    return context.map((item) => `${prefix}${options.fn(item)}${suffix}`).join(separator);
  });
  handlebars.registerHelper("join", (context, separator) => {
    if (!Array.isArray(context))
      return "";
    const sep = typeof separator === "string" ? separator.replace(/\\n/g, `
`).replace(/\\t/g, "\t") : ", ";
    return context.join(sep);
  });
  handlebars.registerHelper("default", (value, defaultValue) => value || defaultValue);
  handlebars.registerHelper("pluralize", (count, singular, plural) => `${count} ${count === 1 ? singular : plural}`);
  handlebars.registerHelper("when", function(lhs, operator, rhs, options) {
    const ops = {
      "==": (a, b) => a === b,
      "===": (a, b) => a === b,
      "!=": (a, b) => a !== b,
      "!==": (a, b) => a !== b,
      ">": (a, b) => a > b,
      "<": (a, b) => a < b,
      ">=": (a, b) => a >= b,
      "<=": (a, b) => a <= b
    };
    const fn = ops[operator];
    if (!fn)
      return options.inverse(this);
    return fn(lhs, rhs) ? options.fn(this) : options.inverse(this);
  });
  handlebars.registerHelper("ifAny", function(...args) {
    const options = args.pop();
    return args.some(Boolean) ? options.fn(this) : options.inverse(this);
  });
  handlebars.registerHelper("ifAll", function(...args) {
    const options = args.pop();
    return args.every(Boolean) ? options.fn(this) : options.inverse(this);
  });
  handlebars.registerHelper("table", function(context, options) {
    if (!Array.isArray(context) || context.length === 0)
      return "";
    const headersStr = options.hash.headers;
    const headers = headersStr?.split("|") ?? [];
    const separator = headers.map(() => "---").join(" | ");
    const headerRow = headers.length > 0 ? `| ${headers.join(" | ")} |
| ${separator} |
` : "";
    const rows = context.map((item) => `| ${options.fn(item).trim()} |`).join(`
`);
    return headerRow + rows;
  });
  handlebars.registerHelper("codeblock", function(options) {
    const lang = options.hash.lang ?? "";
    const content = options.fn(this).trim();
    return `\`\`\`${lang}
${content}
\`\`\``;
  });
  handlebars.registerHelper("xml", function(tag, options) {
    const content = options.fn(this).trim();
    if (!content)
      return "";
    return `<${tag}>
${content}
</${tag}>`;
  });
  handlebars.registerHelper("escapeXml", (value) => {
    if (value == null)
      return "";
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  });
  handlebars.registerHelper("len", (value) => {
    if (Array.isArray(value))
      return value.length;
    if (typeof value === "string")
      return value.length;
    return 0;
  });
  handlebars.registerHelper("add", (a, b) => (a ?? 0) + (b ?? 0));
  handlebars.registerHelper("sub", (a, b) => (a ?? 0) - (b ?? 0));
  handlebars.registerHelper("has", function(collection, item, options) {
    let found = false;
    if (Array.isArray(collection)) {
      found = collection.includes(item);
    } else if (collection instanceof Set) {
      found = collection.has(item);
    } else if (collection instanceof Map) {
      found = collection.has(item);
    } else if (collection && typeof collection === "object") {
      if (typeof item === "string" || typeof item === "number" || typeof item === "symbol") {
        found = item in collection;
      }
    }
    return found ? options.fn(this) : options.inverse(this);
  });
  handlebars.registerHelper("includes", (collection, item) => {
    if (Array.isArray(collection))
      return collection.includes(item);
    if (collection instanceof Set)
      return collection.has(item);
    if (collection instanceof Map)
      return collection.has(item);
    return false;
  });
  handlebars.registerHelper("not", (value) => !value);
  handlebars.registerHelper("jsonStringify", (value) => JSON.stringify(value));
  var compiledTemplateCache = new LRUCache({ max: 256 });
  function compile3(template) {
    const cached = compiledTemplateCache.get(template);
    if (cached)
      return cached;
    const compiled = handlebars.compile(template, { noEscape: true, strict: false });
    compiledTemplateCache.set(template, compiled);
    return compiled;
  }
  function render(template, context = {}) {
    const compiled = compile3(template);
    const rendered = compiled(context ?? {});
    return format2(rendered, { renderPhase: "post-render" });
  }

  // ../scripts/omp-core/pure-utils.ts
  var logger = {
    warn(message) {
      console.warn(message);
    }
  };
  function isPlainObject(value) {
    return Object.getPrototypeOf(value) === Object.prototype || Array.isArray(value);
  }
  function structuredCloneJSON(value) {
    if (!value || typeof value !== "object")
      return value;
    if (isPlainObject(value)) {
      try {
        return structuredClone(value);
      } catch {}
    }
    return JSON.parse(JSON.stringify(value));
  }

  // ../build/upstream/oh-my-pi/packages/utils/src/fetch-retry.ts
  var import_promises = (() => ({}));

  // ../build/upstream/oh-my-pi/packages/ai/src/error/classes.ts
  var MAX_ANTHROPIC_ERROR_BODY_BYTES = 64 * 1024;

  // ../build/upstream/oh-my-pi/packages/ai/src/error/rate-limit.ts
  var QUOTA_EXHAUSTED_BACKOFF_MS = 30 * 60 * 1000;
  var RATE_LIMIT_EXCEEDED_BACKOFF_MS = 30 * 1000;
  var CONCURRENT_LIMIT_BACKOFF_MS = 5 * 1000;
  var MODEL_CAPACITY_BASE_MS = 45 * 1000;
  var MODEL_CAPACITY_JITTER_MS = 30 * 1000;
  var SERVER_ERROR_BACKOFF_MS = 20 * 1000;
  var LONG_RATE_LIMIT_DELAY_MS = 5 * 60 * 1000;

  // ../build/upstream/oh-my-pi/packages/ai/src/error/flags.ts
  var Flag = {
    Class: 4096,
    ThinkingLoop: 65536,
    Transient: 131072,
    Timeout: 262144,
    UsageLimit: 524288,
    StaleResponsesItem: 1048576,
    MalformedFunctionCall: 2097152,
    ProviderFinishError: 4194304,
    EmptyResponse: 8192,
    ContentBlocked: 32768,
    AccountPolicy: 16384,
    ContextOverflow: 8388608,
    AuthFailed: 16777216,
    SilentAbort: 33554432,
    UserInterrupt: 67108864,
    Abort: 134217728,
    Grammar: 268435456,
    FastModeUnsupported: 536870912,
    OAuthExpiry: 1073741824,
    CacheControlUnsupported: 2048,
    PayloadRejected: 2147483648
  };
  var KIND_MASK = Flag.ThinkingLoop | Flag.Transient | Flag.Timeout | Flag.UsageLimit | Flag.StaleResponsesItem | Flag.MalformedFunctionCall | Flag.ProviderFinishError | Flag.EmptyResponse | Flag.ContentBlocked | Flag.AccountPolicy | Flag.ContextOverflow | Flag.AuthFailed | Flag.PayloadRejected | Flag.SilentAbort | Flag.UserInterrupt | Flag.Abort | Flag.Grammar | Flag.FastModeUnsupported | Flag.CacheControlUnsupported | Flag.OAuthExpiry;
  var RETRIABLE_KINDS = Flag.Transient | Flag.UsageLimit | Flag.ThinkingLoop | Flag.StaleResponsesItem | Flag.ProviderFinishError | Flag.EmptyResponse;
  var CONTEXT_OVERFLOW_EVIDENCE_PATTERNS = [
    /prompt is too long/i,
    /input is too long for requested model/i,
    /exceeds the context window/i,
    /input token count.*exceeds the maximum/i,
    /maximum prompt length is \d+/i,
    /reduce the length of the messages/i,
    /maximum context length is \d+ tokens/i,
    /exceeds the available context size/i,
    /\bprompt\s*\(\s*\d+\s+tokens\s*\)\s*\+\s*max\s+tokens\s*\(\s*\d+\s*\)\s+exceeds\s+the\s+context\s*\(\s*\d+\s*\)/i,
    /\bprompt\s*\(\s*\d+\s+tokens\s*\)\s+leaves\s+no\s+room\s+to\s+answer\s+in\s+the\s+context\s*\(\s*\d+\s*\)/i,
    /requested tokens?.*exceed.*context (window|length|size)/i,
    /context (window|length|size).*(exceeded|overflow|too small)/i,
    /(prompt|input).*(too long|too large).*(context|n_ctx)/i,
    /requested tokens?.*(exceeds?|greater than).*(n_ctx|context)/i,
    /greater than the context length/i,
    /context window exceeds limit/i,
    /exceeded model token limit/i,
    /context[_ ]length[_ ]exceeded/i,
    /too many tokens/i,
    /token limit exceeded/i,
    /request_too_large[^\n]*\btokens?\b/i,
    /\btokens?\b[^\n]*request_too_large/i,
    /model_context_window_exceeded/i,
    /prompt filled the context window/i,
    /exceeds the limit of \d+ tokens?\b/i,
    /chat history exceeds the \d+-message limit/i
  ];
  var GENERIC_LIMIT_OVERFLOW_PATTERN = /exceeds the limit of \d+/i;
  var OVERFLOW_PATTERNS = [...CONTEXT_OVERFLOW_EVIDENCE_PATTERNS, GENERIC_LIMIT_OVERFLOW_PATTERN];
  var ERROR_KIND_LABELS = [
    [Flag.ThinkingLoop, "thinking-loop"],
    [Flag.Transient, "transient"],
    [Flag.Timeout, "timeout"],
    [Flag.UsageLimit, "usage-limit"],
    [Flag.StaleResponsesItem, "stale-responses-item"],
    [Flag.MalformedFunctionCall, "malformed-function-call"],
    [Flag.ProviderFinishError, "provider-finish-error"],
    [Flag.EmptyResponse, "empty-response"],
    [Flag.ContentBlocked, "content-blocked"],
    [Flag.AccountPolicy, "account-policy"],
    [Flag.ContextOverflow, "context-overflow"],
    [Flag.PayloadRejected, "payload-rejected"],
    [Flag.AuthFailed, "auth-failed"],
    [Flag.SilentAbort, "silent-abort"],
    [Flag.UserInterrupt, "user-interrupt"],
    [Flag.Abort, "abort"]
  ];

  // ../build/upstream/oh-my-pi/packages/ai/src/error/validation.ts
  class ValidationError extends Error {
    constructor(message, options) {
      super(message, options?.cause === undefined ? undefined : { cause: options.cause });
      this.name = "ValidationError";
    }
  }

  class ToolNotFoundError extends ValidationError {
    constructor(toolName) {
      super(`Tool "${toolName}" not found`);
      this.name = "ToolNotFoundError";
    }
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/types.ts
  function isJsonObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/equality.ts
  function areJsonValuesEqual(left, right) {
    if (Object.is(left, right)) {
      return true;
    }
    if (Array.isArray(left) || Array.isArray(right)) {
      if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
        return false;
      }
      for (let i = 0;i < left.length; i += 1) {
        if (!areJsonValuesEqual(left[i], right[i])) {
          return false;
        }
      }
      return true;
    }
    if (!isJsonObject(left) || !isJsonObject(right)) {
      return false;
    }
    let rightLen = 0;
    for (const _ in right)
      rightLen++;
    let leftLen = 0;
    for (const key in left) {
      leftLen++;
      if (!(key in right) || !areJsonValuesEqual(left[key], right[key]))
        return false;
    }
    return leftLen === rightLen;
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/stamps.ts
  var memos = new WeakMap;
  function stamp(target, key, compute) {
    let slots = memos.get(target);
    if (!slots) {
      slots = new Map;
      memos.set(target, slots);
    }
    const existing = slots.get(key);
    if (existing !== undefined)
      return existing;
    const value = compute(target);
    slots.set(key, value);
    return value;
  }
  var epochs = new WeakMap;
  var __epoch = 0;
  function epochNext() {
    return ++__epoch;
  }
  function once(target, epoch) {
    const cur = epochs.get(target);
    if (cur !== undefined && cur >= epoch)
      return false;
    epochs.set(target, epoch);
    return true;
  }
  var depths = new WeakMap;

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/draft.ts
  var JSON_SCHEMA_DRAFT_2020_12_URI = "https://json-schema.org/draft/2020-12/schema";
  var DRAFT_07_SCHEMA_URIS = {
    "http://json-schema.org/draft-07/schema#": true,
    "https://json-schema.org/draft-07/schema#": true,
    "http://json-schema.org/draft-07/schema": true,
    "https://json-schema.org/draft-07/schema": true
  };
  var SCHEMA_MAP_KEYS = { properties: true, patternProperties: true, dependentSchemas: true };
  var NON_SCHEMA_VALUE_KEYS = {
    const: true,
    default: true,
    enum: true,
    example: true,
    examples: true,
    required: true,
    dependentRequired: true,
    type: true
  };
  function convertRef(value) {
    return value.startsWith("#/definitions/") ? `#/$defs/${value.slice("#/definitions/".length)}` : value;
  }
  function getObjectMap(target, key) {
    const existing = target[key];
    if (isJsonObject(existing))
      return existing;
    const next = {};
    target[key] = next;
    return next;
  }
  function mergeSchemaMap(target, key, value, cache) {
    const map = getObjectMap(target, key);
    for (const name in value) {
      map[name] = upgradeJsonSchemaTo202012Impl(value[name], cache);
    }
  }
  function copySchemaMap(target, key, value, cache) {
    if (!isJsonObject(value)) {
      target[key] = value;
      return;
    }
    mergeSchemaMap(target, key, value, cache);
  }
  function combineSchemas(left, right) {
    if (left === undefined || left === true)
      return right;
    if (right === undefined || right === true)
      return left;
    if (left === false || right === false)
      return false;
    if (areJsonValuesEqual(left, right))
      return left;
    return { allOf: [left, right] };
  }
  function mergeArrayValues(left, right) {
    const merged = [...left];
    for (const value of right) {
      if (!merged.some((existing) => areJsonValuesEqual(existing, value))) {
        merged.push(value);
      }
    }
    return merged;
  }
  function mergePrefixItems(existing, convertedItems) {
    if (!Array.isArray(existing))
      return convertedItems;
    const merged = [...existing];
    for (let index = 0;index < convertedItems.length; index += 1) {
      merged[index] = index in merged ? combineSchemas(merged[index], convertedItems[index]) : convertedItems[index];
    }
    return merged;
  }
  function mergeDependentRequired(target, key, deps) {
    const dependentRequired = getObjectMap(target, "dependentRequired");
    const existing = dependentRequired[key];
    if (existing === undefined) {
      dependentRequired[key] = deps;
      return;
    }
    if (Array.isArray(existing)) {
      dependentRequired[key] = mergeArrayValues(existing, deps);
    }
  }
  function mergeDependentSchema(target, key, schema) {
    const dependentSchemas = getObjectMap(target, "dependentSchemas");
    dependentSchemas[key] = combineSchemas(dependentSchemas[key], schema);
  }
  function convertDependencies(source, target, cache) {
    const dependencies = source.dependencies;
    if (!isJsonObject(dependencies))
      return;
    for (const key in dependencies) {
      const dependency = dependencies[key];
      const converted = upgradeJsonSchemaTo202012Impl(dependency, cache);
      if (Array.isArray(converted)) {
        mergeDependentRequired(target, key, converted);
      } else {
        mergeDependentSchema(target, key, converted);
      }
    }
  }
  function hasNullType(type) {
    return type === "null" || Array.isArray(type) && type.includes("null");
  }
  function hasNullVariant(variants) {
    return variants.some((variant) => isJsonObject(variant) && hasNullType(variant.type));
  }
  function makeNullable(schema) {
    const type = schema.type;
    if (typeof type === "string") {
      if (type !== "null")
        schema.type = [type, "null"];
      return schema;
    }
    if (Array.isArray(type)) {
      if (!type.includes("null"))
        schema.type = [...type, "null"];
      return schema;
    }
    if (Array.isArray(schema.anyOf)) {
      if (!hasNullVariant(schema.anyOf))
        schema.anyOf = [...schema.anyOf, { type: "null" }];
      return schema;
    }
    return { anyOf: [schema, { type: "null" }] };
  }
  function schemaMapNeedsDraft202012Upgrade(value, epoch) {
    if (!isJsonObject(value))
      return false;
    for (const k in value) {
      if (schemaNeedsDraft202012UpgradeImpl(value[k], epoch))
        return true;
    }
    return false;
  }
  function schemaNeedsDraft202012UpgradeImpl(value, epoch) {
    if (Array.isArray(value)) {
      if (!once(value, epoch))
        return false;
      return value.some((entry) => schemaNeedsDraft202012UpgradeImpl(entry, epoch));
    }
    if (!isJsonObject(value))
      return false;
    if (!once(value, epoch))
      return false;
    for (const key in value) {
      const entry = value[key];
      if (key === "$schema") {
        if (typeof entry === "string" && entry in DRAFT_07_SCHEMA_URIS)
          return true;
        continue;
      }
      if (key === "definitions" || key === "dependencies" || key === "additionalItems" || key === "nullable") {
        return true;
      }
      if (key === "$ref") {
        if (typeof entry === "string" && entry.startsWith("#/definitions/"))
          return true;
        continue;
      }
      if (key === "items" && Array.isArray(entry))
        return true;
      if (key === "$defs" || key in SCHEMA_MAP_KEYS) {
        if (schemaMapNeedsDraft202012Upgrade(entry, epoch))
          return true;
        continue;
      }
      if (key in NON_SCHEMA_VALUE_KEYS)
        continue;
      if (schemaNeedsDraft202012UpgradeImpl(entry, epoch))
        return true;
    }
    return false;
  }
  function upgradeJsonSchemaTo202012Impl(value, cache) {
    if (Array.isArray(value)) {
      const cached = cache.get(value);
      if (cached !== undefined)
        return cached;
      const result = [];
      cache.set(value, result);
      for (const entry of value) {
        result.push(upgradeJsonSchemaTo202012Impl(entry, cache));
      }
      return result;
    }
    if (!isJsonObject(value))
      return value;
    const cached = cache.get(value);
    if (cached !== undefined)
      return cached;
    const result = {};
    cache.set(value, result);
    for (const key in value) {
      const entry = value[key];
      if (key === "definitions" || key === "$defs") {
        if (isJsonObject(entry))
          mergeSchemaMap(result, "$defs", entry, cache);
        continue;
      }
      if (key in SCHEMA_MAP_KEYS) {
        copySchemaMap(result, key, entry, cache);
        continue;
      }
      if (key in NON_SCHEMA_VALUE_KEYS) {
        result[key] = entry;
        continue;
      }
      if (key === "dependencies" || key === "additionalItems" || key === "nullable") {
        continue;
      }
      if (key === "$schema") {
        result.$schema = typeof entry === "string" && entry in DRAFT_07_SCHEMA_URIS ? JSON_SCHEMA_DRAFT_2020_12_URI : entry;
        continue;
      }
      if (key === "$ref" && typeof entry === "string") {
        result.$ref = convertRef(entry);
        continue;
      }
      if (key === "items" && Array.isArray(entry)) {
        continue;
      }
      result[key] = upgradeJsonSchemaTo202012Impl(entry, cache);
    }
    if (Array.isArray(value.items)) {
      const convertedItems = upgradeJsonSchemaTo202012Impl(value.items, cache);
      result.prefixItems = mergePrefixItems(result.prefixItems, convertedItems);
      if (value.additionalItems !== undefined && value.additionalItems !== true) {
        result.items = upgradeJsonSchemaTo202012Impl(value.additionalItems, cache);
      } else {
        delete result.items;
      }
    }
    convertDependencies(value, result, cache);
    if (value.nullable === true) {
      const nullable = makeNullable(result);
      if (nullable !== result)
        cache.set(value, nullable);
      return nullable;
    }
    return result;
  }
  function schemaNeedsDraft202012Upgrade(schema) {
    return schemaNeedsDraft202012UpgradeImpl(schema, epochNext());
  }
  function upgradeJsonSchemaTo202012(schema) {
    if (!schemaNeedsDraft202012Upgrade(schema))
      return schema;
    return upgradeJsonSchemaTo202012Impl(schema, new WeakMap);
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/json-schema-validator.ts
  var MAX_REF_DEPTH = 64;
  var seenUnevaluatedWarning = false;
  function getValueIdentity(ctx, value) {
    let id = ctx.objectIds.get(value);
    if (id !== undefined)
      return id;
    id = ctx.nextObjectId.value;
    ctx.nextObjectId.value += 1;
    ctx.objectIds.set(value, id);
    return id;
  }
  function isTagSelectedBranch(branch, value) {
    if (!isRecord(branch) || !isRecord(value))
      return false;
    const props = branch.properties;
    if (!isRecord(props))
      return false;
    let matched = false;
    for (const key in props) {
      const propSchema = props[key];
      if (!isRecord(propSchema))
        continue;
      const hasConst = Object.hasOwn(propSchema, "const");
      const enumValues = Array.isArray(propSchema.enum) ? propSchema.enum : undefined;
      if (!hasConst && !enumValues)
        continue;
      if (!Object.hasOwn(value, key))
        return false;
      const candidate = value[key];
      if (hasConst) {
        if (!areJsonValuesEqual(candidate, propSchema.const))
          return false;
      } else if (enumValues && !enumValues.some((entry) => areJsonValuesEqual(entry, candidate))) {
        return false;
      }
      matched = true;
    }
    return matched;
  }
  function getTagSelectedUnionBranch(branches, value) {
    let selected;
    for (const branch of branches) {
      if (!isTagSelectedBranch(branch, value))
        continue;
      if (selected !== undefined)
        return;
      selected = branch;
    }
    return selected;
  }
  function pushIssue(issues, path, message, options = {}) {
    issues.push({ path: [...path], message, ...options });
  }
  function typeOfJsonValue(value) {
    if (value === null)
      return "null";
    if (Array.isArray(value))
      return "array";
    if (typeof value === "number" && Number.isInteger(value))
      return "integer";
    return typeof value;
  }
  function matchesJsonSchemaType(value, type) {
    switch (type) {
      case "string":
        return typeof value === "string";
      case "number":
        return typeof value === "number" && Number.isFinite(value);
      case "integer":
        return typeof value === "number" && Number.isInteger(value);
      case "boolean":
        return typeof value === "boolean";
      case "object":
        return isRecord(value);
      case "array":
        return Array.isArray(value);
      case "null":
        return value === null;
      default:
        return false;
    }
  }
  function schemaTypes(schema) {
    const raw = schema.type;
    const types = typeof raw === "string" ? [raw] : Array.isArray(raw) ? raw.filter((entry) => typeof entry === "string") : [];
    if (schema.nullable === true && !types.includes("null")) {
      return [...types, "null"];
    }
    return types;
  }
  function decodePointerToken(token) {
    return token.replace(/~1/g, "/").replace(/~0/g, "~");
  }
  function resolveLocalRef(root, ref) {
    if (ref === "#")
      return root;
    if (!ref.startsWith("#/"))
      return;
    let current = root;
    for (const rawToken of ref.slice(2).split("/")) {
      const token = decodePointerToken(rawToken);
      if (!isRecord(current) && !Array.isArray(current))
        return;
      current = current[token];
    }
    return current;
  }
  function isRequiredSet(value) {
    return Array.isArray(value) && value.every((entry) => typeof entry === "string");
  }
  function validateSchemaNode(schema, value, path, ctx, issues) {
    if (schema === true)
      return true;
    if (schema === false) {
      pushIssue(issues, path, "must not match false schema", { keyword: "false" });
      return false;
    }
    if (!isRecord(schema)) {
      pushIssue(issues, path, "schema must be an object or boolean", { keyword: "schema" });
      return false;
    }
    const ref = schema.$ref;
    if (typeof ref === "string") {
      const resolved = resolveLocalRef(ctx.root, ref);
      if (resolved === undefined) {
        pushIssue(issues, path, `unresolved reference ${ref}`, { keyword: "$ref" });
        return false;
      }
      let pairKey;
      if (value !== null && typeof value === "object") {
        pairKey = `${ref}:${getValueIdentity(ctx, value)}`;
        if (ctx.seenPairs.has(pairKey))
          return true;
        ctx.seenPairs.add(pairKey);
      } else {
        if (ctx.refDepth >= MAX_REF_DEPTH) {
          pushIssue(issues, path, "reference depth exceeded", { keyword: "$ref" });
          return false;
        }
        ctx.refDepth += 1;
      }
      const ok = validateSchemaNode(resolved, value, path, ctx, issues);
      if (pairKey !== undefined)
        ctx.seenPairs.delete(pairKey);
      else
        ctx.refDepth -= 1;
      return ok;
    }
    if (value === null && schema.nullable === true)
      return true;
    let valid = true;
    const types = schemaTypes(schema);
    if (types.length > 0 && !types.some((type) => matchesJsonSchemaType(value, type))) {
      pushIssue(issues, path, `expected ${types.join(" or ")}, received ${typeOfJsonValue(value)}`, {
        keyword: "type",
        expectedTypes: types
      });
      return false;
    }
    if ("const" in schema && !areJsonValuesEqual(value, schema.const)) {
      pushIssue(issues, path, "must equal const value", { keyword: "const" });
      valid = false;
    }
    if (Array.isArray(schema.enum) && !schema.enum.some((entry) => areJsonValuesEqual(entry, value))) {
      pushIssue(issues, path, "must be one of the allowed enum values", { keyword: "enum" });
      valid = false;
    }
    for (const keyword of ["anyOf", "oneOf", "allOf"]) {
      const branches = schema[keyword];
      if (!Array.isArray(branches))
        continue;
      if (keyword === "allOf") {
        for (const branch of branches) {
          valid = validateSchemaNode(branch, value, path, ctx, issues) && valid;
        }
        continue;
      }
      let matches = 0;
      let firstIssues;
      let selectedIssues;
      const selectedBranch = getTagSelectedUnionBranch(branches, value);
      for (const branch of branches) {
        const branchIssues = [];
        if (validateSchemaNode(branch, value, path, ctx, branchIssues)) {
          matches += 1;
          continue;
        }
        if (!firstIssues)
          firstIssues = branchIssues;
        if (branch === selectedBranch)
          selectedIssues = branchIssues;
      }
      const branchValid = keyword === "anyOf" ? matches > 0 : matches === 1;
      if (!branchValid) {
        if (matches === 0 && selectedIssues && selectedIssues.length > 0) {
          issues.push(...selectedIssues);
        } else if (matches === 0 && firstIssues && firstIssues.length > 0) {
          for (const branchIssue of firstIssues) {
            issues.push(branchIssue.fromUnionBranch ? branchIssue : { ...branchIssue, fromUnionBranch: true });
          }
        } else {
          pushIssue(issues, path, keyword === "anyOf" ? "must match at least one schema" : "must match exactly one schema", {
            keyword
          });
        }
        valid = false;
      }
    }
    if ("not" in schema) {
      const notIssues = [];
      if (validateSchemaNode(schema.not, value, path, ctx, notIssues)) {
        pushIssue(issues, path, "must not match excluded schema", { keyword: "not" });
        valid = false;
      }
    }
    if ("if" in schema) {
      const ifIssues = [];
      const ifOk = validateSchemaNode(schema.if, value, path, ctx, ifIssues);
      const branch = ifOk ? schema.then : schema.else;
      if (branch !== undefined) {
        valid = validateSchemaNode(branch, value, path, ctx, issues) && valid;
      }
    }
    if ((("unevaluatedProperties" in schema) || ("unevaluatedItems" in schema)) && !seenUnevaluatedWarning) {
      seenUnevaluatedWarning = true;
      logger.warn("JSON Schema unevaluatedProperties/unevaluatedItems are not enforced by the in-tree validator; treating as permissive");
    }
    if (isRecord(value)) {
      valid = validateObjectKeywords(schema, value, path, ctx, issues) && valid;
    }
    if (Array.isArray(value)) {
      valid = validateArrayKeywords(schema, value, path, ctx, issues) && valid;
    }
    if (typeof value === "string") {
      valid = validateStringKeywords(schema, value, path, issues) && valid;
    }
    if (typeof value === "number" && Number.isFinite(value)) {
      valid = validateNumberKeywords(schema, value, path, issues) && valid;
    }
    return valid;
  }
  function validateObjectKeywords(schema, value, path, ctx, issues) {
    let valid = true;
    const properties = isRecord(schema.properties) ? schema.properties : {};
    if (isRequiredSet(schema.required)) {
      for (const key of schema.required) {
        if (!(key in value)) {
          pushIssue(issues, [...path, key], "is required", { keyword: "required" });
          valid = false;
        }
      }
    }
    for (const key in properties) {
      if (!(key in value))
        continue;
      valid = validateSchemaNode(properties[key], value[key], [...path, key], ctx, issues) && valid;
    }
    if (schema.propertyNames !== undefined) {
      for (const key of Object.keys(value)) {
        valid = validateSchemaNode(schema.propertyNames, key, [...path, key], ctx, issues) && valid;
      }
    }
    const known = new Set(Object.keys(properties));
    if (isRecord(schema.patternProperties)) {
      const patternProperties = schema.patternProperties;
      for (const pattern in patternProperties) {
        const patternSchema = patternProperties[pattern];
        let re;
        try {
          re = new RegExp(pattern);
        } catch {
          pushIssue(issues, path, `invalid patternProperties regex ${pattern}`, { keyword: "patternProperties" });
          valid = false;
          continue;
        }
        for (const key in value) {
          if (!re.test(key))
            continue;
          known.add(key);
          valid = validateSchemaNode(patternSchema, value[key], [...path, key], ctx, issues) && valid;
        }
      }
    }
    if (isRecord(schema.dependentRequired)) {
      const dependentRequired = schema.dependentRequired;
      for (const key in dependentRequired) {
        const deps = dependentRequired[key];
        if (!(key in value))
          continue;
        if (!Array.isArray(deps))
          continue;
        for (const dep of deps) {
          if (typeof dep !== "string")
            continue;
          if (!(dep in value)) {
            pushIssue(issues, [...path, dep], `is required when "${key}" is present`, {
              keyword: "dependentRequired"
            });
            valid = false;
          }
        }
      }
    }
    if (isRecord(schema.dependentSchemas)) {
      const dependentSchemas = schema.dependentSchemas;
      for (const key in dependentSchemas) {
        if (!(key in value))
          continue;
        valid = validateSchemaNode(dependentSchemas[key], value, path, ctx, issues) && valid;
      }
    }
    const additional = schema.additionalProperties;
    if (additional === false) {
      for (const key of Object.keys(value)) {
        if (known.has(key))
          continue;
        pushIssue(issues, [...path, key], "must not be present", { keyword: "additionalProperties" });
        valid = false;
      }
    } else if (additional !== undefined && additional !== true) {
      for (const key in value) {
        if (known.has(key))
          continue;
        valid = validateSchemaNode(additional, value[key], [...path, key], ctx, issues) && valid;
      }
    }
    if (typeof schema.minProperties === "number" && Object.keys(value).length < schema.minProperties) {
      pushIssue(issues, path, `must have at least ${schema.minProperties} properties`, { keyword: "minProperties" });
      valid = false;
    }
    if (typeof schema.maxProperties === "number" && Object.keys(value).length > schema.maxProperties) {
      pushIssue(issues, path, `must have at most ${schema.maxProperties} properties`, { keyword: "maxProperties" });
      valid = false;
    }
    return valid;
  }
  function validateArrayKeywords(schema, value, path, ctx, issues) {
    let valid = true;
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      pushIssue(issues, path, `must have at least ${schema.minItems} items`, { keyword: "minItems" });
      valid = false;
    }
    if (typeof schema.maxItems === "number" && value.length > schema.maxItems) {
      pushIssue(issues, path, `must have at most ${schema.maxItems} items`, { keyword: "maxItems" });
      valid = false;
    }
    if (schema.uniqueItems === true) {
      for (let i = 0;i < value.length; i += 1) {
        for (let j = i + 1;j < value.length; j += 1) {
          if (!areJsonValuesEqual(value[i], value[j]))
            continue;
          pushIssue(issues, [...path, j], "must be unique", { keyword: "uniqueItems" });
          valid = false;
        }
      }
    }
    const prefixItems = Array.isArray(schema.prefixItems) ? schema.prefixItems : undefined;
    const items = schema.items;
    if (Array.isArray(items)) {
      pushIssue(issues, path, "array-valued items is not valid in JSON Schema 2020-12; use prefixItems", {
        keyword: "items"
      });
      valid = false;
    } else if (prefixItems) {
      const limit = Math.min(prefixItems.length, value.length);
      for (let i = 0;i < limit; i += 1) {
        valid = validateSchemaNode(prefixItems[i], value[i], [...path, i], ctx, issues) && valid;
      }
      if (items !== undefined) {
        for (let i = prefixItems.length;i < value.length; i += 1) {
          valid = validateSchemaNode(items, value[i], [...path, i], ctx, issues) && valid;
        }
      }
    } else if (items !== undefined) {
      for (let i = 0;i < value.length; i += 1) {
        valid = validateSchemaNode(items, value[i], [...path, i], ctx, issues) && valid;
      }
    }
    if (schema.contains !== undefined) {
      const minContains = typeof schema.minContains === "number" ? schema.minContains : 1;
      const maxContains = typeof schema.maxContains === "number" ? schema.maxContains : Infinity;
      let count = 0;
      for (let i = 0;i < value.length; i += 1) {
        const containsIssues = [];
        if (validateSchemaNode(schema.contains, value[i], [...path, i], ctx, containsIssues)) {
          count += 1;
        }
      }
      if (count < minContains) {
        pushIssue(issues, path, `must contain at least ${minContains} matching item(s)`, { keyword: "contains" });
        valid = false;
      }
      if (count > maxContains) {
        pushIssue(issues, path, `must contain at most ${maxContains} matching item(s)`, { keyword: "maxContains" });
        valid = false;
      }
    }
    return valid;
  }
  function validateStringKeywords(schema, value, path, issues) {
    let valid = true;
    if (typeof schema.minLength === "number" && value.length < schema.minLength) {
      pushIssue(issues, path, `must be at least ${schema.minLength} characters`, { keyword: "minLength" });
      valid = false;
    }
    if (typeof schema.maxLength === "number" && value.length > schema.maxLength) {
      pushIssue(issues, path, `must be at most ${schema.maxLength} characters`, { keyword: "maxLength" });
      valid = false;
    }
    if (typeof schema.pattern === "string") {
      try {
        if (!new RegExp(schema.pattern).test(value)) {
          pushIssue(issues, path, "must match pattern", { keyword: "pattern" });
          valid = false;
        }
      } catch {
        pushIssue(issues, path, "schema pattern is invalid", { keyword: "pattern" });
        valid = false;
      }
    }
    return valid;
  }
  function validateNumberKeywords(schema, value, path, issues) {
    let valid = true;
    if (typeof schema.minimum === "number" && value < schema.minimum) {
      pushIssue(issues, path, `must be >= ${schema.minimum}`, { keyword: "minimum" });
      valid = false;
    }
    if (typeof schema.maximum === "number" && value > schema.maximum) {
      pushIssue(issues, path, `must be <= ${schema.maximum}`, { keyword: "maximum" });
      valid = false;
    }
    if (typeof schema.exclusiveMinimum === "number" && value <= schema.exclusiveMinimum) {
      pushIssue(issues, path, `must be > ${schema.exclusiveMinimum}`, { keyword: "exclusiveMinimum" });
      valid = false;
    }
    if (typeof schema.exclusiveMaximum === "number" && value >= schema.exclusiveMaximum) {
      pushIssue(issues, path, `must be < ${schema.exclusiveMaximum}`, { keyword: "exclusiveMaximum" });
      valid = false;
    }
    if (schema.exclusiveMinimum === true && typeof schema.minimum === "number" && value <= schema.minimum) {
      pushIssue(issues, path, `must be > ${schema.minimum}`, { keyword: "exclusiveMinimum" });
      valid = false;
    }
    if (schema.exclusiveMaximum === true && typeof schema.maximum === "number" && value >= schema.maximum) {
      pushIssue(issues, path, `must be < ${schema.maximum}`, { keyword: "exclusiveMaximum" });
      valid = false;
    }
    if (typeof schema.multipleOf === "number" && schema.multipleOf > 0) {
      const quotient = value / schema.multipleOf;
      if (Math.abs(quotient - Math.round(quotient)) > Number.EPSILON * 10) {
        pushIssue(issues, path, `must be a multiple of ${schema.multipleOf}`, { keyword: "multipleOf" });
        valid = false;
      }
    }
    return valid;
  }
  function validateSchemaValueInRoot(schema, value, root) {
    const issues = [];
    const success = validateSchemaNode(schema, value, [], { root, seenPairs: new Set, objectIds: new WeakMap, nextObjectId: { value: 0 }, refDepth: 0 }, issues);
    return { success, issues };
  }
  function validateJsonSchemaValue(schema, value, root = schema) {
    return validateSchemaValueInRoot(schema, value, root);
  }
  function isJsonSchemaValueValid(schema, value, root = schema) {
    return validateSchemaValueInRoot(schema, value, root).success;
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/schema/wire.ts
  function isArkSchema(value) {
    return typeof value === "function" && typeof value.toJsonSchema === "function" && typeof value.assert === "function";
  }
  function isArkJsonAst(value) {
    if (Array.isArray(value))
      return value.some(isArkJsonAst);
    if (!isRecord(value))
      return false;
    if (typeof value.domain === "string" || Object.hasOwn(value, "unit"))
      return true;
    if (value.proto === "Array" && Object.hasOwn(value, "sequence"))
      return true;
    const required = value.required;
    return Array.isArray(required) && required.some((entry) => isRecord(entry) && typeof entry.key === "string" && ("value" in entry));
  }
  function parseArkObjectKey(key) {
    const match = /^(.*?)\s*\/\*\*\s*([\s\S]*?)\s*\*\/\s*$/.exec(key);
    if (!match)
      return { name: key };
    return { name: match[1].trim(), description: match[2].trim() };
  }
  function withArkKeyDescription(schema, description) {
    if (!description)
      return schema;
    if (isRecord(schema)) {
      if (typeof schema.description !== "string")
        schema.description = description;
      return schema;
    }
    return { anyOf: [schema], description };
  }
  function arkJsonAstToWire(value) {
    if (typeof value === "string") {
      switch (value) {
        case "string":
        case "number":
        case "integer":
        case "boolean":
        case "object":
          return { type: value };
        case "unknown":
          return {};
        default:
          return {};
      }
    }
    if (Array.isArray(value)) {
      if (value.every((item) => isRecord(item) && Object.hasOwn(item, "unit"))) {
        return { enum: value.map((item) => item.unit) };
      }
      return { anyOf: value.map(arkJsonAstToWire) };
    }
    if (!isRecord(value))
      return {};
    if (Object.hasOwn(value, "unit"))
      return { const: value.unit };
    if (value.proto === "Array" && Object.hasOwn(value, "sequence")) {
      return { type: "array", items: arkJsonAstToWire(value.sequence) };
    }
    if (value.domain === "object") {
      const properties = {};
      const required = [];
      const addEntry = (entry, isRequired) => {
        if (!isRecord(entry) || typeof entry.key !== "string" || !("value" in entry))
          return;
        const key = parseArkObjectKey(entry.key);
        properties[key.name] = withArkKeyDescription(arkJsonAstToWire(entry.value), key.description);
        if (isRequired)
          required.push(key.name);
      };
      if (Array.isArray(value.required)) {
        for (const entry of value.required)
          addEntry(entry, true);
      }
      if (Array.isArray(value.optional)) {
        for (const entry of value.optional)
          addEntry(entry, false);
      }
      const schema = { type: "object", properties };
      if (required.length > 0)
        schema.required = required;
      return schema;
    }
    if (typeof value.domain === "string")
      return { type: value.domain };
    return {};
  }
  var kJsonWireSchema = Symbol("omp.schema.json.wire");
  var kArkWireSchema = Symbol("omp.schema.ark.wire");
  var kStrippedSchema = Symbol("omp.schema.descriptions.stripped");
  function postProcessJsonSchema(schema) {
    walk2(schema);
    normalizeArkPropertyComments(schema);
    normalizeEmptySchemas(schema);
    return schema;
  }
  var NULLABLE_SCALAR_TYPES = new Set(["string", "number", "integer", "boolean"]);
  var SCHEMA_DEFINING_SIBLING_KEYS = new Set([
    "$ref",
    "additionalProperties",
    "allOf",
    "anyOf",
    "const",
    "contains",
    "enum",
    "if",
    "items",
    "not",
    "oneOf",
    "patternProperties",
    "prefixItems",
    "properties",
    "propertyNames",
    "then",
    "else",
    "unevaluatedItems",
    "unevaluatedProperties"
  ]);
  function hasSchemaDefiningSibling(schema) {
    for (const key in schema) {
      if (key !== "anyOf" && SCHEMA_DEFINING_SIBLING_KEYS.has(key))
        return true;
    }
    return false;
  }
  function isNullVariant(schema) {
    return schema.type === "null" && Object.keys(schema).length === 1;
  }
  function isScalarVariant(schema) {
    return typeof schema.type === "string" && NULLABLE_SCALAR_TYPES.has(schema.type);
  }
  function copyNullableScalarConstraints(schema, scalarVariant) {
    for (const key in scalarVariant) {
      if (key === "type" || key === "enum" || key === "const" || Object.hasOwn(schema, key))
        continue;
      schema[key] = scalarVariant[key];
    }
    if (Object.hasOwn(scalarVariant, "const")) {
      schema.enum = [scalarVariant.const, null];
      return;
    }
    const enumValues = scalarVariant.enum;
    if (Array.isArray(enumValues)) {
      schema.enum = enumValues.includes(null) ? enumValues : [...enumValues, null];
    }
  }
  function rewriteNullableScalarAnyOf(schema) {
    if (hasSchemaDefiningSibling(schema))
      return;
    const variants = schema.anyOf;
    if (!Array.isArray(variants) || variants.length !== 2)
      return;
    let scalarVariant;
    let scalarType;
    let sawNull = false;
    for (const variant of variants) {
      if (!isRecord(variant))
        return;
      if (isNullVariant(variant)) {
        if (sawNull)
          return;
        sawNull = true;
        continue;
      }
      if (!isScalarVariant(variant) || scalarVariant)
        return;
      scalarVariant = variant;
      scalarType = variant.type;
    }
    if (!sawNull || !scalarVariant || !scalarType)
      return;
    delete schema.anyOf;
    copyNullableScalarConstraints(schema, scalarVariant);
    schema.type = [scalarType, "null"];
  }
  var SCHEMA_VALUE_KEYS = [
    "additionalProperties",
    "unevaluatedProperties",
    "unevaluatedItems",
    "items",
    "contains",
    "propertyNames",
    "if",
    "then",
    "else",
    "not"
  ];
  var SCHEMA_MAP_KEYS2 = ["properties", "patternProperties", "$defs", "definitions"];
  var SCHEMA_ARRAY_KEYS = ["anyOf", "oneOf", "allOf", "prefixItems"];
  function normalizeArkPropertyComments(node) {
    if (Array.isArray(node)) {
      for (const child of node)
        normalizeArkPropertyComments(child);
      return;
    }
    if (!isRecord(node))
      return;
    const obj = node;
    const properties = obj.properties;
    if (isRecord(properties)) {
      const required = Array.isArray(obj.required) ? obj.required : undefined;
      if (required) {
        obj.required = required.map((key) => typeof key === "string" ? parseArkObjectKey(key).name : key);
      }
      for (const key of Object.keys(properties)) {
        const parsed = parseArkObjectKey(key);
        const targetKey = parsed.name;
        let propertySchema = properties[key];
        if (parsed.description) {
          propertySchema = withArkKeyDescription(propertySchema, parsed.description);
          delete properties[key];
          properties[targetKey] = propertySchema;
        }
        normalizeArkPropertyComments(propertySchema);
      }
    }
    for (const key of SCHEMA_VALUE_KEYS) {
      if (Object.hasOwn(obj, key))
        normalizeArkPropertyComments(obj[key]);
    }
    for (const mapKey of SCHEMA_MAP_KEYS2) {
      if (mapKey === "properties")
        continue;
      const map = obj[mapKey];
      if (isRecord(map)) {
        for (const key in map)
          normalizeArkPropertyComments(map[key]);
      }
    }
    for (const arrayKey of SCHEMA_ARRAY_KEYS) {
      const array = obj[arrayKey];
      if (Array.isArray(array)) {
        for (const child of array)
          normalizeArkPropertyComments(child);
      }
    }
  }
  function isEmptyObject(val) {
    if (val === null || typeof val !== "object" || Array.isArray(val))
      return false;
    return Object.keys(val).length === 0;
  }
  function homogeneousEnumScalarType(values) {
    if (values.length === 0)
      return;
    let inferred;
    for (const value of values) {
      let scalar;
      switch (typeof value) {
        case "string":
          scalar = "string";
          break;
        case "boolean":
          scalar = "boolean";
          break;
        case "number":
          scalar = "number";
          break;
        default:
          return;
      }
      if (inferred === undefined)
        inferred = scalar;
      else if (inferred !== scalar)
        return;
    }
    return inferred;
  }
  function inferBareEnumScalarType(obj) {
    if ("type" in obj || !Array.isArray(obj.enum))
      return;
    const inferred = homogeneousEnumScalarType(obj.enum);
    if (inferred !== undefined)
      obj.type = inferred;
  }
  function collapseConstUnionAnyOf(obj) {
    if (hasSchemaDefiningSibling(obj) || "type" in obj)
      return;
    const variants = obj.anyOf;
    if (!Array.isArray(variants) || variants.length < 2)
      return;
    const values = [];
    let branchDescription;
    let describedCount = 0;
    for (const variant of variants) {
      if (!isRecord(variant) || !Object.hasOwn(variant, "const"))
        return;
      for (const key in variant) {
        if (key !== "const" && key !== "description")
          return;
      }
      const desc = variant.description;
      if (typeof desc === "string") {
        if (describedCount === 0)
          branchDescription = desc;
        else if (desc !== branchDescription)
          return;
        describedCount++;
      }
      values.push(variant.const);
    }
    if (describedCount !== 0 && describedCount !== variants.length)
      return;
    if (describedCount === variants.length && typeof obj.description === "string" && obj.description !== branchDescription) {
      return;
    }
    const scalarType = homogeneousEnumScalarType(values);
    if (scalarType === undefined)
      return;
    delete obj.anyOf;
    obj.type = scalarType;
    obj.enum = values;
    if (typeof obj.description !== "string" && branchDescription !== undefined) {
      obj.description = branchDescription;
    }
  }
  function walk2(node) {
    if (Array.isArray(node)) {
      for (const child of node)
        walk2(child);
      return;
    }
    if (!node || typeof node !== "object")
      return;
    const obj = node;
    rewriteNullableScalarAnyOf(obj);
    inferBareEnumScalarType(obj);
    collapseConstUnionAnyOf(obj);
    for (const k in obj)
      walk2(obj[k]);
  }
  function normalizeEmptySchemas(node) {
    if (Array.isArray(node)) {
      for (const child of node)
        normalizeEmptySchemas(child);
      return;
    }
    if (!node || typeof node !== "object")
      return;
    const obj = node;
    for (const key of SCHEMA_VALUE_KEYS) {
      if (Object.hasOwn(obj, key) && isEmptyObject(obj[key]))
        obj[key] = true;
    }
    for (const mapKey of SCHEMA_MAP_KEYS2) {
      const map = obj[mapKey];
      if (map !== null && typeof map === "object" && !Array.isArray(map)) {
        for (const k in map) {
          if (isEmptyObject(map[k]))
            map[k] = true;
        }
      }
    }
    for (const arrKey of SCHEMA_ARRAY_KEYS) {
      const arr = obj[arrKey];
      if (Array.isArray(arr)) {
        for (let i = 0;i < arr.length; i++) {
          if (isEmptyObject(arr[i]))
            arr[i] = true;
        }
      }
    }
    for (const k in obj)
      normalizeEmptySchemas(obj[k]);
  }
  function closeDeclaredObjects(node) {
    if (Array.isArray(node)) {
      for (const child of node)
        closeDeclaredObjects(child);
      return;
    }
    if (!node || typeof node !== "object")
      return;
    const obj = node;
    const isObjectType = obj.type === "object" || Array.isArray(obj.type) && obj.type.includes("object");
    if (isObjectType && obj.properties !== undefined && !("additionalProperties" in obj) && !("patternProperties" in obj)) {
      obj.additionalProperties = false;
    }
    for (const key of SCHEMA_VALUE_KEYS) {
      if (Object.hasOwn(obj, key))
        closeDeclaredObjects(obj[key]);
    }
    for (const mapKey of SCHEMA_MAP_KEYS2) {
      const map = obj[mapKey];
      if (map !== null && typeof map === "object" && !Array.isArray(map)) {
        for (const k in map)
          closeDeclaredObjects(map[k]);
      }
    }
    for (const arrKey of SCHEMA_ARRAY_KEYS) {
      const arr = obj[arrKey];
      if (Array.isArray(arr))
        for (const child of arr)
          closeDeclaredObjects(child);
    }
  }
  function isUnconstrainedSchema(val) {
    return val === true || isEmptyObject(val);
  }
  function pruneArkUndefinedUnionBranches(node) {
    if (Array.isArray(node)) {
      for (const child of node)
        pruneArkUndefinedUnionBranches(child);
      return;
    }
    if (!node || typeof node !== "object")
      return;
    const obj = node;
    for (const unionKey of ["anyOf", "oneOf"]) {
      const branches = obj[unionKey];
      if (!Array.isArray(branches))
        continue;
      const concrete = branches.filter((branch) => !isUnconstrainedSchema(branch));
      if (concrete.length === branches.length || concrete.length === 0)
        continue;
      const only = concrete.length === 1 ? concrete[0] : undefined;
      if (only !== undefined && isRecord(only)) {
        delete obj[unionKey];
        for (const key in only) {
          if (!(key in obj))
            obj[key] = only[key];
        }
      } else {
        obj[unionKey] = concrete;
      }
    }
    for (const key of SCHEMA_VALUE_KEYS) {
      if (Object.hasOwn(obj, key))
        pruneArkUndefinedUnionBranches(obj[key]);
    }
    for (const mapKey of SCHEMA_MAP_KEYS2) {
      const map = obj[mapKey];
      if (map !== null && typeof map === "object" && !Array.isArray(map)) {
        for (const key in map) {
          pruneArkUndefinedUnionBranches(map[key]);
        }
      }
    }
    for (const arrKey of SCHEMA_ARRAY_KEYS) {
      const arr = obj[arrKey];
      if (Array.isArray(arr))
        for (const child of arr)
          pruneArkUndefinedUnionBranches(child);
    }
  }
  function arkToWireSchema(schema) {
    return stamp(schema, kArkWireSchema, (s) => {
      const raw = s.toJsonSchema({ target: "draft-2020-12", fallback: (ctx) => ctx.base });
      delete raw.$schema;
      pruneArkUndefinedUnionBranches(raw);
      const upgraded = postProcessJsonSchema(upgradeJsonSchemaTo202012(raw));
      closeDeclaredObjects(upgraded);
      return upgraded;
    });
  }
  function toolWireSchema(tool) {
    const params = tool.parameters;
    if (isArkSchema(params))
      return arkToWireSchema(params);
    return stamp(params, kJsonWireSchema, (p) => {
      const raw = isArkJsonAst(p) ? arkJsonAstToWire(p) : structuredCloneJSON(p);
      const upgraded = upgradeJsonSchemaTo202012(raw);
      return postProcessJsonSchema(upgraded);
    });
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/tool-call-arguments.ts
  var INVALID_ARGUMENTS_RAW_LIMIT = 512;
  var TRUNCATED_SUFFIX = /… \[truncated \d+ chars\]$/;
  function boundRawToolArguments(raw) {
    if (raw.length <= INVALID_ARGUMENTS_RAW_LIMIT)
      return raw;
    if (TRUNCATED_SUFFIX.exec(raw)?.index === INVALID_ARGUMENTS_RAW_LIMIT)
      return raw;
    return `${raw.slice(0, INVALID_ARGUMENTS_RAW_LIMIT)}… [truncated ${raw.length - INVALID_ARGUMENTS_RAW_LIMIT} chars]`;
  }

  // ../build/upstream/oh-my-pi/packages/ai/src/utils/validation.ts
  var JSON_NUMBER_PATTERN = /^[+-]?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
  var NUMERIC_STRING_PATTERN = /^[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
  function matchesExpectedType(value, expectedTypes) {
    return expectedTypes.some((type2) => {
      switch (type2) {
        case "string":
          return typeof value === "string";
        case "number":
          return typeof value === "number" && Number.isFinite(value);
        case "integer":
          return typeof value === "number" && Number.isInteger(value);
        case "boolean":
          return typeof value === "boolean";
        case "null":
          return value === null;
        case "array":
          return Array.isArray(value);
        case "object":
          return value !== null && typeof value === "object" && !Array.isArray(value);
        default:
          return false;
      }
    });
  }
  function tryParseNumberString(value, expectedTypes) {
    if (!expectedTypes.includes("number") && !expectedTypes.includes("integer")) {
      return { value, changed: false };
    }
    const trimmed = value.trim();
    if (!trimmed || !NUMERIC_STRING_PATTERN.test(trimmed)) {
      return { value, changed: false };
    }
    const parsed = Number(trimmed);
    if (!Number.isFinite(parsed)) {
      return { value, changed: false };
    }
    if (!matchesExpectedType(parsed, expectedTypes)) {
      return { value, changed: false };
    }
    return { value: parsed, changed: true };
  }
  function tryCoerceBoolean(value, expectedTypes) {
    if (!expectedTypes.includes("boolean")) {
      return { value, changed: false };
    }
    if (typeof value === "number") {
      if (value === 0)
        return { value: false, changed: true };
      if (value === 1)
        return { value: true, changed: true };
      return { value, changed: false };
    }
    if (typeof value !== "string") {
      return { value, changed: false };
    }
    switch (value.trim().toLowerCase()) {
      case "true":
      case "1":
      case "yes":
      case "on":
        return { value: true, changed: true };
      case "false":
      case "0":
      case "no":
      case "off":
        return { value: false, changed: true };
      default:
        return { value, changed: false };
    }
  }
  function tryCoerceBooleanToNumber(value, expectedTypes) {
    if (!expectedTypes.includes("number") && !expectedTypes.includes("integer")) {
      return { value, changed: false };
    }
    if (typeof value !== "boolean") {
      return { value, changed: false };
    }
    return { value: value ? 1 : 0, changed: true };
  }
  function tryCoerceString(value, expectedTypes, allowLossy) {
    if (!expectedTypes.includes("string") || typeof value === "string" || value === null || value === undefined) {
      return { value, changed: false };
    }
    if (Array.isArray(value) || typeof value === "object") {
      if (!allowLossy)
        return { value, changed: false };
      try {
        const stringified = JSON.stringify(value);
        if (stringified === undefined)
          return { value, changed: false };
        return { value: stringified, changed: true };
      } catch {
        return { value, changed: false };
      }
    }
    if (typeof value === "function") {
      return { value, changed: false };
    }
    return { value: String(value), changed: true };
  }
  function tryCoerceForExpectedTypes(value, expectedTypes, allowLossy) {
    if (typeof value === "string") {
      const parsed = tryParseJsonForTypes(value, expectedTypes);
      if (parsed.changed)
        return parsed;
      return tryCoerceBoolean(value, expectedTypes);
    }
    const booleanCoercion = tryCoerceBoolean(value, expectedTypes);
    if (booleanCoercion.changed)
      return booleanCoercion;
    const numericCoercion = tryCoerceBooleanToNumber(value, expectedTypes);
    if (numericCoercion.changed)
      return numericCoercion;
    return tryCoerceString(value, expectedTypes, allowLossy);
  }
  function tryParseLeadingJsonContainer(value) {
    const firstChar = value[0];
    const closingChar = firstChar === "{" ? "}" : firstChar === "[" ? "]" : undefined;
    if (!closingChar)
      return;
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let index = 0;index < value.length; index += 1) {
      const char = value[index];
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (char === "\\") {
          escaped = true;
          continue;
        }
        if (char === '"')
          inString = false;
        continue;
      }
      if (char === '"') {
        inString = true;
        continue;
      }
      if (char === firstChar) {
        depth += 1;
        continue;
      }
      if (char !== closingChar)
        continue;
      depth -= 1;
      if (depth !== 0)
        continue;
      const prefix = value.slice(0, index + 1);
      try {
        return JSON.parse(prefix);
      } catch {
        const cleaned = cleanLiteralEscapes(prefix);
        if (cleaned !== prefix) {
          try {
            return JSON.parse(cleaned);
          } catch {}
        }
        const escapedControls = escapeRawControlsInJsonStrings(prefix);
        if (escapedControls !== prefix) {
          try {
            return JSON.parse(escapedControls);
          } catch {}
        }
        return tryHealMalformedJson(prefix);
      }
    }
    return;
  }
  function cleanLiteralEscapes(value) {
    let result = "";
    let inString = false;
    let i = 0;
    while (i < value.length) {
      const ch = value[i];
      if (inString) {
        if (ch === "\\" && i + 1 < value.length) {
          result += ch + value[i + 1];
          i += 2;
          continue;
        }
        if (ch === '"')
          inString = false;
        result += ch;
        i += 1;
        continue;
      }
      if (ch === '"') {
        inString = true;
        result += ch;
        i += 1;
        continue;
      }
      if (ch === "\\" && i + 1 < value.length) {
        const next = value[i + 1];
        if (next === "n" || next === "t" || next === "r") {
          result += " ";
          i += 2;
          continue;
        }
      }
      result += ch;
      i += 1;
    }
    return result;
  }
  function escapeRawControlsInJsonStrings(value) {
    let result = "";
    let inString = false;
    let escaped = false;
    let changed = false;
    for (let i = 0;i < value.length; i += 1) {
      const ch = value[i];
      if (inString) {
        if (escaped) {
          result += ch;
          escaped = false;
          continue;
        }
        if (ch === "\\") {
          result += ch;
          escaped = true;
          continue;
        }
        if (ch === '"') {
          result += ch;
          inString = false;
          continue;
        }
        const code = ch.charCodeAt(0);
        if (code < 32) {
          changed = true;
          switch (ch) {
            case `
`:
              result += "\\n";
              break;
            case "\r":
              result += "\\r";
              break;
            case "\t":
              result += "\\t";
              break;
            case "\b":
              result += "\\b";
              break;
            case "\f":
              result += "\\f";
              break;
            default:
              result += `\\u${code.toString(16).padStart(4, "0")}`;
          }
          continue;
        }
        result += ch;
        continue;
      }
      if (ch === '"') {
        inString = true;
      }
      result += ch;
    }
    return changed ? result : value;
  }
  var MAX_HEAL_DISTANCE = 3;
  var BRACKET_CHARS = ["[", "]", "{", "}"];
  function tryHealMalformedJson(value) {
    try {
      return JSON.parse(value);
    } catch {}
    const tailStart = Math.max(0, value.length - (MAX_HEAL_DISTANCE * 2 + 1));
    for (let i = tailStart;i < value.length; i += 1) {
      const candidate = value.slice(0, i) + value.slice(i + 1);
      try {
        return JSON.parse(candidate);
      } catch {}
    }
    for (let i = tailStart;i < value.length; i += 1) {
      const original = value[i];
      for (const replacement of BRACKET_CHARS) {
        if (replacement === original)
          continue;
        const candidate = value.slice(0, i) + replacement + value.slice(i + 1);
        try {
          return JSON.parse(candidate);
        } catch {}
      }
    }
    return;
  }
  var MAX_NESTED_JSON_STRING_PARSE_DEPTH = 3;
  function acceptParsedJsonForTypes(parsed, source, expectedTypes, depth) {
    if (parsed === null && source.trim() === "null") {
      return { value: null, changed: true };
    }
    if (matchesExpectedType(parsed, expectedTypes)) {
      return { value: parsed, changed: true };
    }
    if (typeof parsed === "string" && !expectedTypes.includes("string") && depth < MAX_NESTED_JSON_STRING_PARSE_DEPTH) {
      return tryParseJsonForTypes(parsed, expectedTypes, depth + 1);
    }
    return { value: source, changed: false };
  }
  function looksLikeJsonContainerString(value) {
    if (typeof value !== "string")
      return false;
    const trimmed = value.trimStart();
    if (trimmed.startsWith("{")) {
      const body = trimmed.slice(1);
      return body.trimStart().startsWith('"') || body.includes(":") || body.trimStart().startsWith("}");
    }
    if (!trimmed.startsWith("["))
      return false;
    const firstItem = trimmed.slice(1).trimStart();
    return firstItem.startsWith("{") || firstItem.startsWith("[") || firstItem.startsWith('"') || firstItem.startsWith("]") || firstItem.startsWith("true") || firstItem.startsWith("false") || firstItem.startsWith("null") || /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?:\s*(?:,|\]|$))/.test(firstItem);
  }
  function tryParseJsonForTypes(value, expectedTypes, depth = 0) {
    const trimmed = value.trim();
    if (!trimmed)
      return { value, changed: false };
    const numberCoercion = tryParseNumberString(trimmed, expectedTypes);
    if (numberCoercion.changed) {
      return numberCoercion;
    }
    const looksJsonObject = trimmed.startsWith("{") && looksLikeJsonContainerString(trimmed);
    const looksJsonArray = trimmed.startsWith("[") && looksLikeJsonContainerString(trimmed);
    const looksJsonString = trimmed.startsWith('"') && !expectedTypes.includes("string");
    const looksJsonLiteral = trimmed === "true" || trimmed === "false" || trimmed === "null" || JSON_NUMBER_PATTERN.test(trimmed);
    if (!looksJsonObject && !looksJsonArray && !looksJsonString && !looksJsonLiteral) {
      return { value, changed: false };
    }
    try {
      const parsed = JSON.parse(trimmed);
      const accepted = acceptParsedJsonForTypes(parsed, trimmed, expectedTypes, depth);
      if (accepted.changed)
        return accepted;
    } catch {
      if (looksJsonObject || looksJsonArray) {
        const escapedControls = escapeRawControlsInJsonStrings(trimmed);
        if (escapedControls !== trimmed) {
          try {
            const parsed = JSON.parse(escapedControls);
            const accepted = acceptParsedJsonForTypes(parsed, escapedControls, expectedTypes, depth);
            if (accepted.changed)
              return accepted;
          } catch {}
        }
        const leading = tryParseLeadingJsonContainer(trimmed);
        if (leading !== undefined) {
          const accepted = acceptParsedJsonForTypes(leading, trimmed, expectedTypes, depth);
          if (accepted.changed)
            return accepted;
        }
        const healed = tryHealMalformedJson(trimmed);
        if (healed !== undefined) {
          const accepted = acceptParsedJsonForTypes(healed, trimmed, expectedTypes, depth);
          if (accepted.changed)
            return accepted;
        }
      }
      return { value, changed: false };
    }
    return { value, changed: false };
  }
  function pathToPointer(path) {
    if (path.length === 0)
      return "";
    return `/${path.map((seg) => String(seg).replace(/~/g, "~0").replace(/\//g, "~1")).join("/")}`;
  }
  function decodeJsonPointer(pointer) {
    if (!pointer)
      return [];
    return pointer.split("/").slice(1).map((segment) => segment.replace(/~1/g, "/").replace(/~0/g, "~"));
  }
  function getValueAtPointer(root, pointer) {
    if (!pointer)
      return root;
    const segments = decodeJsonPointer(pointer);
    let current = root;
    for (const segment of segments) {
      if (current === null || current === undefined)
        return;
      if (Array.isArray(current)) {
        const index = Number(segment);
        if (!Number.isInteger(index))
          return;
        current = current[index];
        continue;
      }
      if (typeof current !== "object")
        return;
      current = current[segment];
    }
    return current;
  }
  function setValueAtPointer(root, pointer, value) {
    if (!pointer)
      return value;
    const segments = decodeJsonPointer(pointer);
    let current = root;
    for (let index = 0;index < segments.length - 1; index += 1) {
      const segment = segments[index];
      if (current === null || current === undefined)
        return root;
      if (Array.isArray(current)) {
        const arrayIndex = Number(segment);
        if (!Number.isInteger(arrayIndex))
          return root;
        current = current[arrayIndex];
        continue;
      }
      if (typeof current !== "object")
        return root;
      current = current[segment];
    }
    const lastSegment = segments[segments.length - 1];
    if (Array.isArray(current)) {
      const arrayIndex = Number(lastSegment);
      if (!Number.isInteger(arrayIndex))
        return root;
      current[arrayIndex] = value;
      return root;
    }
    if (typeof current !== "object" || current === null)
      return root;
    current[lastSegment] = value;
    return root;
  }
  function deleteValueAtPointer(root, pointer) {
    if (!pointer)
      return root;
    const segments = decodeJsonPointer(pointer);
    if (segments.length === 0)
      return root;
    return deleteAtSegment(root, segments, 0);
  }
  function deleteAtSegment(node, segments, depth) {
    const segment = segments[depth];
    const isLeaf = depth === segments.length - 1;
    if (Array.isArray(node)) {
      const index = Number(segment);
      if (!Number.isInteger(index) || index < 0 || index >= node.length)
        return node;
      if (isLeaf) {
        const next = node.slice();
        next.splice(index, 1);
        return next;
      }
      const child = deleteAtSegment(node[index], segments, depth + 1);
      if (child === node[index])
        return node;
      const next = node.slice();
      next[index] = child;
      return next;
    }
    if (typeof node !== "object" || node === null)
      return node;
    const obj = node;
    if (!Object.hasOwn(obj, segment))
      return node;
    if (isLeaf) {
      const { [segment]: _omit, ...rest } = obj;
      return rest;
    }
    const child = deleteAtSegment(obj[segment], segments, depth + 1);
    if (child === obj[segment])
      return node;
    return { ...obj, [segment]: child };
  }
  function branchMatchesSchema(branch, value, root = branch) {
    return isJsonSchemaValueValid(branch, value, root);
  }
  function normalizeOptionalNullsForSchema(schema, value, isRoot = true, root = schema, insideContent = false, speculativeUnion = false) {
    if (value === null || value === undefined)
      return { value, changed: false };
    if (schema === null || typeof schema !== "object")
      return { value, changed: false };
    const schemaObject = schema;
    const normalizeAnyOfLike = (keyword) => {
      const branches = schemaObject[keyword];
      if (!Array.isArray(branches))
        return { value, changed: false };
      for (const branch of branches) {
        if (!branchMatchesSchema(branch, value, root))
          continue;
        const normalized = normalizeOptionalNullsForSchema(branch, value, isRoot, root, insideContent, speculativeUnion);
        if (branchMatchesSchema(branch, normalized.value, root) && branchMatchesSchema(schemaObject, normalized.value, root)) {
          return normalized;
        }
      }
      const selectedBranch = getTagSelectedUnionBranch(branches, value);
      for (const branch of branches) {
        const normalized = normalizeOptionalNullsForSchema(branch, value, isRoot, root, insideContent, speculativeUnion || selectedBranch !== branch);
        if (!normalized.changed)
          continue;
        const branchContext = {
          kind: "json",
          json: branch,
          root,
          union: schemaObject,
          unionBranches: branches,
          speculativeUnion
        };
        const result = validateContext(branchContext, normalized.value);
        if (result.success && branchMatchesSchema(branch, normalized.value, root))
          return normalized;
        const repaired = runCoercionPasses(branchContext, normalized.value, result, isRoot, insideContent);
        if (repaired.result.success && branchMatchesSchema(branch, repaired.args, root)) {
          return { value: repaired.args, changed: true };
        }
      }
      return { value, changed: false };
    };
    const anyOfNormalization = normalizeAnyOfLike("anyOf");
    if (anyOfNormalization.changed)
      return anyOfNormalization;
    const oneOfNormalization = normalizeAnyOfLike("oneOf");
    if (oneOfNormalization.changed)
      return oneOfNormalization;
    if (Array.isArray(schemaObject.allOf)) {
      let changed = false;
      let nextValue = value;
      for (const branch of schemaObject.allOf) {
        const normalized = normalizeOptionalNullsForSchema(branch, nextValue, isRoot, root, insideContent, speculativeUnion);
        if (!normalized.changed)
          continue;
        nextValue = normalized.value;
        changed = true;
      }
      if (changed)
        return { value: nextValue, changed: true };
    }
    if (Array.isArray(value)) {
      const itemSchema = schemaObject.items;
      if (itemSchema === null || typeof itemSchema !== "object" || Array.isArray(itemSchema)) {
        return { value, changed: false };
      }
      let changed = false;
      let nextValue = value;
      for (let i = 0;i < value.length; i += 1) {
        const normalized = normalizeOptionalNullsForSchema(itemSchema, value[i], false, root, insideContent, speculativeUnion);
        if (!normalized.changed)
          continue;
        if (!changed) {
          nextValue = [...value];
          changed = true;
        }
        nextValue[i] = normalized.value;
      }
      return { value: changed ? nextValue : value, changed };
    }
    if ((schemaObject.type === "number" || schemaObject.type === "integer") && typeof value === "string") {
      return tryParseNumberString(value, [schemaObject.type]);
    }
    if (schemaObject.type !== "object")
      return { value, changed: false };
    if (typeof value !== "object" || value === null)
      return { value, changed: false };
    if (Array.isArray(value))
      return { value, changed: false };
    if (schemaObject.properties === null || typeof schemaObject.properties !== "object") {
      return { value, changed: false };
    }
    const properties = schemaObject.properties;
    const required = new Set(Array.isArray(schemaObject.required) ? schemaObject.required : []);
    let changed = false;
    let nextValue = value;
    for (const [key, propertySchema] of Object.entries(properties)) {
      if (!(key in nextValue))
        continue;
      const currentValue = nextValue[key];
      const isNullish = currentValue === null || currentValue === "null";
      const isInvalidEmptyString = currentValue === "" && !required.has(key) && !branchMatchesSchema(propertySchema, currentValue, root);
      if ((isNullish || isInvalidEmptyString) && !required.has(key)) {
        if (!changed) {
          nextValue = { ...nextValue };
          changed = true;
        }
        delete nextValue[key];
        continue;
      }
      if (isNullish && propertySchema && typeof propertySchema === "object") {
        const propertyObject = propertySchema;
        if ("default" in propertyObject) {
          if (!changed) {
            nextValue = { ...nextValue };
            changed = true;
          }
          nextValue[key] = structuredCloneJSON(propertyObject.default);
          continue;
        }
      }
      const normalized = normalizeOptionalNullsForSchema(propertySchema, currentValue, false, root, insideContent || CONTENT_CARRYING_KEYS.has(key), speculativeUnion);
      if (!normalized.changed)
        continue;
      if (!changed) {
        nextValue = { ...nextValue };
        changed = true;
      }
      nextValue[key] = normalized.value;
    }
    if (!isRoot && !speculativeUnion && schemaObject.additionalProperties === false) {
      const knownKeys = new Set(Object.keys(properties));
      for (const key of Object.keys(nextValue)) {
        if (knownKeys.has(key))
          continue;
        const v = nextValue[key];
        if (v !== null && v !== "null")
          continue;
        if (!changed) {
          nextValue = { ...nextValue };
          changed = true;
        }
        delete nextValue[key];
      }
    }
    return { value: changed ? nextValue : value, changed };
  }
  function decodeJsonPointerToken(token) {
    return token.replace(/~1/g, "/").replace(/~0/g, "~");
  }
  function resolveLocalJsonSchemaRef(root, ref) {
    if (ref === "#")
      return root;
    if (!ref.startsWith("#/"))
      return;
    let current = root;
    for (const rawToken of ref.slice(2).split("/")) {
      const token = decodeJsonPointerToken(rawToken);
      if (current === null || typeof current !== "object")
        return;
      current = current[token];
    }
    return current;
  }
  function normalizeEnumStringWhitespace(schema, value, root = schema, refs = new Set) {
    if (value === null || value === undefined)
      return { value, changed: false };
    if (schema === null || typeof schema !== "object")
      return { value, changed: false };
    const schemaObject = schema;
    const ref = schemaObject.$ref;
    if (typeof ref === "string") {
      if (refs.has(ref))
        return { value, changed: false };
      const resolved = resolveLocalJsonSchemaRef(root, ref);
      if (resolved === undefined)
        return { value, changed: false };
      return normalizeEnumStringWhitespace(resolved, value, root, new Set([...refs, ref]));
    }
    const normalizeAnyOfLike = (keyword) => {
      const branches = schemaObject[keyword];
      if (!Array.isArray(branches))
        return { value, changed: false };
      if (branches.some((branch) => branchMatchesSchema(branch, value, root)))
        return { value, changed: false };
      for (const branch of branches) {
        const normalized = normalizeEnumStringWhitespace(branch, value, root, refs);
        if (!normalized.changed)
          continue;
        if (branchMatchesSchema(branch, normalized.value, root))
          return normalized;
      }
      return { value, changed: false };
    };
    const anyOfNormalization = normalizeAnyOfLike("anyOf");
    if (anyOfNormalization.changed)
      return anyOfNormalization;
    const oneOfNormalization = normalizeAnyOfLike("oneOf");
    if (oneOfNormalization.changed)
      return oneOfNormalization;
    if (Array.isArray(schemaObject.allOf)) {
      let changed = false;
      let nextValue = value;
      for (const branch of schemaObject.allOf) {
        const normalized = normalizeEnumStringWhitespace(branch, nextValue, root, refs);
        if (!normalized.changed)
          continue;
        nextValue = normalized.value;
        changed = true;
      }
      if (changed)
        return { value: nextValue, changed: true };
    }
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed !== value) {
        const enumValues = schemaObject.enum;
        if (Array.isArray(enumValues) && !enumValues.includes(value) && enumValues.includes(trimmed)) {
          return { value: trimmed, changed: true };
        }
        const constValue = schemaObject.const;
        if (typeof constValue === "string" && trimmed === constValue) {
          return { value: trimmed, changed: true };
        }
      }
      return { value, changed: false };
    }
    if (Array.isArray(value)) {
      let changed = false;
      let nextValue = value;
      const prefixItems = schemaObject.prefixItems;
      if (Array.isArray(prefixItems)) {
        for (let i = 0;i < value.length && i < prefixItems.length; i += 1) {
          const itemSchema = prefixItems[i];
          const normalized = normalizeEnumStringWhitespace(itemSchema, value[i], root, refs);
          if (!normalized.changed)
            continue;
          if (!changed) {
            nextValue = [...value];
            changed = true;
          }
          nextValue[i] = normalized.value;
        }
      }
      const itemSchema = schemaObject.items;
      if (itemSchema !== null && typeof itemSchema === "object" && !Array.isArray(itemSchema)) {
        for (let i = 0;i < value.length; i += 1) {
          if (Array.isArray(prefixItems) && i < prefixItems.length)
            continue;
          const normalized = normalizeEnumStringWhitespace(itemSchema, nextValue[i], root, refs);
          if (!normalized.changed)
            continue;
          if (!changed) {
            nextValue = [...value];
            changed = true;
          }
          nextValue[i] = normalized.value;
        }
      }
      return { value: changed ? nextValue : value, changed };
    }
    if (typeof value !== "object")
      return { value, changed: false };
    const properties = schemaObject.properties;
    if (!properties || typeof properties !== "object")
      return { value, changed: false };
    const propsObject = properties;
    const valueObject = value;
    let changed = false;
    let nextValue = valueObject;
    for (const [key, propertySchema] of Object.entries(propsObject)) {
      if (!(key in nextValue))
        continue;
      const normalized = normalizeEnumStringWhitespace(propertySchema, nextValue[key], root, refs);
      if (!normalized.changed)
        continue;
      if (!changed) {
        nextValue = { ...nextValue };
        changed = true;
      }
      nextValue[key] = normalized.value;
    }
    return { value: changed ? nextValue : valueObject, changed };
  }
  var IDENTIFIER_STRING_KEYS = new Set([
    "path",
    "paths",
    "file",
    "file_path",
    "filePath",
    "filepath",
    "url",
    "uri",
    "title",
    "label"
  ]);
  var CONTENT_CARRYING_KEYS = new Set(["content", "input", "body", "text", "command", "code"]);
  var TRAILING_LINE_TERMINATOR_RE = /[\r\n]+$/;
  function trimTrailingLineTerminators(input) {
    if (!TRAILING_LINE_TERMINATOR_RE.test(input))
      return input;
    return input.replace(TRAILING_LINE_TERMINATOR_RE, "");
  }
  function trimIdentifierStringLeaf(input) {
    if (typeof input === "string") {
      const trimmed = trimTrailingLineTerminators(input);
      return trimmed === input ? input : trimmed;
    }
    if (Array.isArray(input)) {
      let changed = false;
      let next = input;
      for (let i = 0;i < input.length; i += 1) {
        const item = input[i];
        if (typeof item !== "string")
          continue;
        const trimmed = trimTrailingLineTerminators(item);
        if (trimmed === item)
          continue;
        if (!changed) {
          next = input.slice();
          changed = true;
        }
        next[i] = trimmed;
      }
      return changed ? next : input;
    }
    return input;
  }
  function normalizeIdentifierStringWhitespace(value, insideContent = false) {
    if (insideContent)
      return { value, changed: false };
    if (Array.isArray(value)) {
      let changed = false;
      let next = value;
      for (let i = 0;i < value.length; i += 1) {
        const normalized = normalizeIdentifierStringWhitespace(value[i]);
        if (!normalized.changed)
          continue;
        if (!changed) {
          next = [...value];
          changed = true;
        }
        next[i] = normalized.value;
      }
      return { value: changed ? next : value, changed };
    }
    if (value === null || typeof value !== "object")
      return { value, changed: false };
    const source = value;
    let changed = false;
    let out = source;
    for (const [key, entry] of Object.entries(source)) {
      let nextEntry = entry;
      if (CONTENT_CARRYING_KEYS.has(key))
        continue;
      if (IDENTIFIER_STRING_KEYS.has(key)) {
        const trimmed = trimIdentifierStringLeaf(entry);
        if (trimmed !== entry)
          nextEntry = trimmed;
      }
      const nested = normalizeIdentifierStringWhitespace(nextEntry);
      if (nested.changed)
        nextEntry = nested.value;
      if (nextEntry === entry)
        continue;
      if (!changed) {
        out = { ...source };
        changed = true;
      }
      out[key] = nextEntry;
    }
    return { value: changed ? out : value, changed };
  }
  var MAX_KEY_DECODE_DEPTH = 3;
  function decodeDoubleEncodedKey(key) {
    let current = key;
    let decoded = null;
    for (let depth = 0;depth < MAX_KEY_DECODE_DEPTH; depth += 1) {
      if (current.length < 2 || current[0] !== '"' || current[current.length - 1] !== '"')
        break;
      let parsed;
      try {
        parsed = JSON.parse(current);
      } catch {
        break;
      }
      if (typeof parsed !== "string")
        break;
      current = parsed;
      decoded = current;
    }
    return decoded;
  }
  function normalizeDoubleEncodedKeys(value) {
    if (Array.isArray(value)) {
      let changed = false;
      let next = value;
      for (let i = 0;i < value.length; i += 1) {
        const normalized = normalizeDoubleEncodedKeys(value[i]);
        if (!normalized.changed)
          continue;
        if (!changed) {
          next = [...value];
          changed = true;
        }
        next[i] = normalized.value;
      }
      return { value: changed ? next : value, changed };
    }
    if (value === null || typeof value !== "object")
      return { value, changed: false };
    const source = value;
    let changed = false;
    const out = {};
    for (const [key, entry] of Object.entries(source)) {
      const normalizedChild = normalizeDoubleEncodedKeys(entry);
      const nextChild = normalizedChild.changed ? normalizedChild.value : entry;
      const decodedKey = decodeDoubleEncodedKey(key);
      const targetKey = decodedKey !== null && decodedKey !== key && !Object.hasOwn(source, decodedKey) && !Object.hasOwn(out, decodedKey) ? decodedKey : key;
      if (targetKey !== key || normalizedChild.changed)
        changed = true;
      Object.defineProperty(out, targetKey, {
        value: nextChild,
        writable: true,
        enumerable: true,
        configurable: true
      });
    }
    return { value: changed ? out : value, changed };
  }
  function schemaAcceptsStringAndArray(schema) {
    if (Array.isArray(schema.type) && schema.type.includes("string") && schema.type.includes("array")) {
      return true;
    }
    for (const key of ["anyOf", "oneOf"]) {
      const branches = schema[key];
      if (!Array.isArray(branches))
        continue;
      let hasString = false;
      let hasArray = false;
      for (const branch of branches) {
        if (!branch || typeof branch !== "object")
          continue;
        const branchType = branch.type;
        if (branchType === "string" || Array.isArray(branchType) && branchType.includes("string")) {
          hasString = true;
        }
        if (branchType === "array" || Array.isArray(branchType) && branchType.includes("array")) {
          hasArray = true;
        }
        if (hasString && hasArray)
          return true;
      }
    }
    return false;
  }
  function schemaNodeAcceptsArray(schema) {
    if (!schema || typeof schema !== "object")
      return false;
    const schemaObject = schema;
    const schemaType = schemaObject.type;
    return schemaType === "array" || Array.isArray(schemaType) && schemaType.includes("array");
  }
  function parsedArrayMatchesArrayBranch(schema, value) {
    if (schemaNodeAcceptsArray(schema)) {
      return isJsonSchemaValueValid(schema, value);
    }
    for (const key of ["anyOf", "oneOf"]) {
      const branches = schema[key];
      if (!Array.isArray(branches))
        continue;
      const branchList = branches;
      for (const branch of branchList) {
        if (!schemaNodeAcceptsArray(branch))
          continue;
        if (isJsonSchemaValueValid(branch, value))
          return true;
      }
    }
    return false;
  }
  function normalizeStringEncodedArrayUnions(schema, value) {
    if (value === null || value === undefined)
      return { value, changed: false };
    if (schema === null || typeof schema !== "object")
      return { value, changed: false };
    const schemaObject = schema;
    if (typeof value === "string" && schemaAcceptsStringAndArray(schemaObject)) {
      const trimmed = value.trim();
      if (!trimmed.startsWith("["))
        return { value, changed: false };
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          const candidate = normalizeDoubleEncodedKeys(parsed).value;
          if (parsedArrayMatchesArrayBranch(schemaObject, candidate)) {
            return { value: candidate, changed: true };
          }
        }
      } catch {}
      return { value, changed: false };
    }
    if (Array.isArray(value)) {
      const itemSchema = schemaObject.items;
      if (!itemSchema || typeof itemSchema !== "object" || Array.isArray(itemSchema)) {
        return { value, changed: false };
      }
      let changed = false;
      let nextValue = value;
      for (let i = 0;i < value.length; i += 1) {
        const normalized = normalizeStringEncodedArrayUnions(itemSchema, value[i]);
        if (!normalized.changed)
          continue;
        if (!changed) {
          nextValue = [...value];
          changed = true;
        }
        nextValue[i] = normalized.value;
      }
      return { value: changed ? nextValue : value, changed };
    }
    if (schemaObject.type !== "object")
      return { value, changed: false };
    if (typeof value !== "object" || value === null)
      return { value, changed: false };
    const properties = schemaObject.properties;
    if (!properties || typeof properties !== "object")
      return { value, changed: false };
    const propsObject = properties;
    const valueObject = value;
    let changed = false;
    let nextValue = valueObject;
    for (const [key, propertySchema] of Object.entries(propsObject)) {
      if (!(key in nextValue))
        continue;
      const normalized = normalizeStringEncodedArrayUnions(propertySchema, nextValue[key]);
      if (!normalized.changed)
        continue;
      if (!changed) {
        nextValue = { ...nextValue };
        changed = true;
      }
      nextValue[key] = normalized.value;
    }
    return { value: changed ? nextValue : valueObject, changed };
  }
  function singleRequiredStringKey(schema) {
    if (!schema || typeof schema !== "object" || Array.isArray(schema))
      return;
    const obj = schema;
    if (obj.type !== "object")
      return;
    const properties = obj.properties;
    if (!properties || typeof properties !== "object")
      return;
    const keys = Object.keys(properties);
    if (keys.length !== 1)
      return;
    const key = keys[0];
    const required = obj.required;
    if (!Array.isArray(required) || required.length !== 1 || required[0] !== key)
      return;
    const propertySchema = properties[key];
    if (!propertySchema || typeof propertySchema !== "object")
      return;
    return propertySchema.type === "string" ? key : undefined;
  }
  function normalizeSingleStringField(schema, value) {
    const key = singleRequiredStringKey(schema);
    if (key === undefined)
      return { value, changed: false };
    if (typeof value !== "object" || value === null || Array.isArray(value))
      return { value, changed: false };
    const record = value;
    if (record[key] !== undefined)
      return { value, changed: false };
    for (const candidate in record) {
      if (candidate === key || !Object.hasOwn(record, candidate))
        continue;
      const candidateValue = record[candidate];
      if (typeof candidateValue !== "string")
        continue;
      const next = { ...record, [key]: candidateValue };
      delete next[candidate];
      return { value: next, changed: true };
    }
    return { value, changed: false };
  }
  var MAX_FLATTENED_INDEX = 1e5;
  var FLATTENED_IDENT_RE = /^[A-Za-z_$][A-Za-z0-9_$]*/;
  var FLATTENED_INDEX_RE = /^\[(\d+)\]/;
  function parseFlattenedPath(key) {
    if (key.length === 0)
      return null;
    const steps = [];
    const first = FLATTENED_IDENT_RE.exec(key);
    if (!first)
      return null;
    steps.push({ kind: "prop", name: first[0], index: 0 });
    let pos = first[0].length;
    let sawIndex = false;
    while (pos < key.length) {
      if (key[pos] === ".") {
        pos++;
        const m = FLATTENED_IDENT_RE.exec(key.slice(pos));
        if (!m || m[0].length === 0)
          return null;
        steps.push({ kind: "prop", name: m[0], index: 0 });
        pos += m[0].length;
        continue;
      }
      if (key[pos] === "[") {
        const m = FLATTENED_INDEX_RE.exec(key.slice(pos));
        if (!m)
          return null;
        const index = Number(m[1]);
        if (!Number.isSafeInteger(index) || index < 0 || index > MAX_FLATTENED_INDEX)
          return null;
        steps.push({ kind: "index", index });
        sawIndex = true;
        pos += m[0].length;
        continue;
      }
      return null;
    }
    if (!sawIndex)
      return null;
    return { steps };
  }
  function buildFlattenedPath(root, steps, value) {
    let node = root;
    for (let i = 0;i < steps.length - 1; i++) {
      const step = steps[i];
      const nextIsArray = steps[i + 1].kind === "index";
      if (step.kind === "prop") {
        const obj = node;
        if (obj === null || typeof obj !== "object" || Array.isArray(obj))
          return false;
        const existing = Object.hasOwn(obj, step.name) ? obj[step.name] : undefined;
        let child;
        if (existing === undefined && !Object.hasOwn(obj, step.name)) {
          child = nextIsArray ? [] : {};
        } else {
          if (Array.isArray(existing) !== nextIsArray)
            return false;
          child = existing;
        }
        Object.defineProperty(obj, step.name, {
          value: child,
          writable: true,
          enumerable: true,
          configurable: true
        });
        node = child;
        continue;
      }
      const arr = node;
      if (!Array.isArray(arr))
        return false;
      while (arr.length <= step.index)
        arr.push(undefined);
      let child = arr[step.index];
      if (child === undefined) {
        child = nextIsArray ? [] : {};
        arr[step.index] = child;
      } else {
        if (Array.isArray(child)) {
          if (!nextIsArray)
            return false;
        } else if (typeof child !== "object" || child === null) {
          return false;
        } else if (nextIsArray) {
          return false;
        }
      }
      node = child;
    }
    const last = steps[steps.length - 1];
    if (last.kind === "prop") {
      const obj = node;
      if (obj === null || typeof obj !== "object" || Array.isArray(obj))
        return false;
      Object.defineProperty(obj, last.name, {
        value,
        writable: true,
        enumerable: true,
        configurable: true
      });
    } else {
      const arr = node;
      if (!Array.isArray(arr))
        return false;
      while (arr.length <= last.index)
        arr.push(undefined);
      arr[last.index] = value;
    }
    return true;
  }
  function normalizeFlattenedArrayProperties(value) {
    if (!isPlainRecord(value))
      return { value, changed: false };
    const source = value;
    const out = {};
    let changed = false;
    for (const [key, entry] of Object.entries(source)) {
      const parsed = parseFlattenedPath(key);
      if (!parsed) {
        if (Object.hasOwn(out, key))
          return { value, changed: false };
        Object.defineProperty(out, key, { value: entry, writable: true, enumerable: true, configurable: true });
        continue;
      }
      if (entry === undefined)
        continue;
      if (!buildFlattenedPath(out, parsed.steps, entry))
        return { value, changed: false };
      changed = true;
    }
    if (!changed)
      return { value, changed: false };
    return { value: out, changed: true };
  }
  function coerceArgsFromIssues(args, issues) {
    if (issues.length === 0)
      return { value: args, changed: false };
    let changed = false;
    let owned = false;
    let nextArgs = args;
    for (const issue of issues) {
      if (issue.keyword === "unrecognized") {
        if (issue.unionBranch)
          continue;
        const previous = nextArgs;
        nextArgs = deleteValueAtPointer(nextArgs, issue.instancePath);
        if (nextArgs !== previous)
          changed = true;
        continue;
      }
      if (issue.keyword !== "type")
        continue;
      if (issue.expectedTypes.length === 0)
        continue;
      const currentValue = getValueAtPointer(nextArgs, issue.instancePath);
      const result = tryCoerceForExpectedTypes(currentValue, issue.expectedTypes, true);
      let coercedValue = result.changed ? result.value : undefined;
      if (coercedValue === undefined && issue.expectedTypes.includes("array") && !issue.unionBranch && currentValue !== undefined && !Array.isArray(currentValue)) {
        const objectCoercion = typeof currentValue === "string" ? tryParseJsonForTypes(currentValue, ["object"]) : { value: currentValue, changed: false };
        if (objectCoercion.changed || !looksLikeJsonContainerString(currentValue)) {
          coercedValue = [objectCoercion.changed ? objectCoercion.value : currentValue];
        }
      }
      if (coercedValue === undefined)
        continue;
      if (!owned) {
        nextArgs = structuredCloneJSON(nextArgs);
        owned = true;
        changed = true;
      }
      nextArgs = setValueAtPointer(nextArgs, issue.instancePath, coercedValue);
    }
    return { value: changed ? nextArgs : args, changed };
  }
  var kValidationContext = Symbol("ai.validationContext");
  function getValidationContext(tool) {
    return stamp(tool.parameters, kValidationContext, (params) => isArkSchema(params) ? { kind: "arktype", ark: params, json: arkToWireSchema(params) } : { kind: "json", json: upgradeJsonSchemaTo202012(params) });
  }
  function isPlainRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function preserveUnknownRootFields(input, parsed) {
    if (!isPlainRecord(input) || !isPlainRecord(parsed))
      return parsed;
    return { ...input, ...parsed };
  }
  function flattenJsonSchemaIssues(issues, speculativeUnion = false) {
    return issues.map((issue) => {
      const unionBranch = speculativeUnion || issue.fromUnionBranch === true;
      if (issue.keyword === "additionalProperties") {
        return {
          keyword: "unrecognized",
          instancePath: pathToPointer(issue.path),
          expectedTypes: [],
          unionBranch
        };
      }
      return {
        keyword: issue.keyword === "type" ? "type" : "other",
        instancePath: pathToPointer(issue.path),
        expectedTypes: issue.expectedTypes ?? [],
        unionBranch
      };
    });
  }
  function formatIssuePath(path) {
    return path.length === 0 ? "root" : path.map((seg) => String(seg)).join("/");
  }
  function validateContext(ctx, value) {
    if (ctx.kind === "arktype") {
      const out = ctx.ark(value);
      if (!(out instanceof type.errors)) {
        return { success: true, value: preserveUnknownRootFields(value, out) };
      }
      const jr = validateJsonSchemaValue(ctx.json, value);
      const flatIssues = jr.success ? [] : flattenJsonSchemaIssues(jr.issues);
      return {
        success: false,
        flatIssues,
        messages: out.map((e) => `  - ${formatIssuePath(e.path)}: ${e.message}`)
      };
    }
    const result = validateJsonSchemaValue(ctx.union ?? ctx.json, value, ctx.root);
    if (result.success)
      return { success: true, value };
    return {
      success: false,
      flatIssues: flattenJsonSchemaIssues(result.issues, ctx.speculativeUnion),
      messages: result.issues.map((issue) => `  - ${formatIssuePath(issue.path)}: ${issue.message}`)
    };
  }
  var SPILL_KEY_OPEN = "<arg_key>";
  var SPILL_KEY_CLOSE = "</arg_key>";
  var SPILL_VALUE_OPEN = "<arg_value>";
  var SPILL_VALUE_CLOSE = "</arg_value>";
  var SPILL_TOOL_CLOSE = "</tool_call>";
  var SPILL_KEY_PATTERN = /^[\w.$-]{1,128}$/;
  function skipSpillWhitespace(text, from) {
    let at = from;
    while (at < text.length && ` 
	\r`.includes(text[at]))
      at++;
    return at;
  }
  function isSpillPairStart(text, at) {
    if (!text.startsWith(SPILL_KEY_OPEN, at))
      return false;
    const keyStart = at + SPILL_KEY_OPEN.length;
    const keyEnd = text.indexOf(SPILL_KEY_CLOSE, keyStart);
    if (keyEnd === -1 || !SPILL_KEY_PATTERN.test(text.slice(keyStart, keyEnd)))
      return false;
    const valueAt = skipSpillWhitespace(text, keyEnd + SPILL_KEY_CLOSE.length);
    return text.startsWith(SPILL_VALUE_OPEN, valueAt);
  }
  function findSpillValueEnd(text, from) {
    const close = text.indexOf(SPILL_VALUE_CLOSE, from);
    let wrong = text.indexOf(SPILL_KEY_CLOSE, from);
    let open = text.indexOf(SPILL_KEY_OPEN, from);
    while (true) {
      const candidates = [close, wrong, open].filter((index) => index !== -1);
      if (candidates.length === 0)
        return { end: text.length, next: text.length };
      const at = Math.min(...candidates);
      if (at === close)
        return { end: at, next: at + SPILL_VALUE_CLOSE.length };
      if (at === wrong) {
        const follow = skipSpillWhitespace(text, at + SPILL_KEY_CLOSE.length);
        if (follow >= text.length || text.startsWith(SPILL_KEY_OPEN, follow) || text.startsWith(SPILL_TOOL_CLOSE, follow)) {
          return { end: at, next: at + SPILL_KEY_CLOSE.length };
        }
        wrong = text.indexOf(SPILL_KEY_CLOSE, at + 1);
        continue;
      }
      if (isSpillPairStart(text, at)) {
        let end = at;
        while (end > from && ` 
	\r`.includes(text[end - 1]))
          end--;
        return { end, next: at };
      }
      open = text.indexOf(SPILL_KEY_OPEN, at + 1);
    }
  }
  function parseSpilledPairs(text) {
    const pairs = [];
    let at = skipSpillWhitespace(text, 0);
    while (at < text.length) {
      if (text.startsWith(SPILL_TOOL_CLOSE, at)) {
        at = skipSpillWhitespace(text, at + SPILL_TOOL_CLOSE.length);
        return at >= text.length ? pairs : null;
      }
      if (!text.startsWith(SPILL_KEY_OPEN, at))
        return null;
      const keyStart = at + SPILL_KEY_OPEN.length;
      const keyEnd = text.indexOf(SPILL_KEY_CLOSE, keyStart);
      if (keyEnd === -1)
        return null;
      const key = text.slice(keyStart, keyEnd);
      if (!SPILL_KEY_PATTERN.test(key))
        return null;
      at = skipSpillWhitespace(text, keyEnd + SPILL_KEY_CLOSE.length);
      if (!text.startsWith(SPILL_VALUE_OPEN, at))
        return null;
      at += SPILL_VALUE_OPEN.length;
      const { end, next } = findSpillValueEnd(text, at);
      pairs.push([key, text.slice(at, end)]);
      at = skipSpillWhitespace(text, next);
    }
    return pairs;
  }
  function splitSpilledValue(text) {
    let wrong = text.indexOf(SPILL_KEY_CLOSE);
    let open = text.indexOf(SPILL_KEY_OPEN);
    while (wrong !== -1 || open !== -1) {
      if (wrong !== -1 && (open === -1 || wrong < open)) {
        const pairs = parseSpilledPairs(text.slice(wrong + SPILL_KEY_CLOSE.length));
        if (pairs)
          return { head: text.slice(0, wrong), pairs };
        wrong = text.indexOf(SPILL_KEY_CLOSE, wrong + 1);
        continue;
      }
      if (isSpillPairStart(text, open)) {
        const pairs = parseSpilledPairs(text.slice(open));
        if (pairs && pairs.length > 0)
          return { head: text.slice(0, open).trimEnd(), pairs };
      }
      open = text.indexOf(SPILL_KEY_OPEN, open + 1);
    }
    return null;
  }
  function healInbandArgSpill(value) {
    if (!isPlainRecord(value))
      return { value, changed: false };
    let changed = false;
    const out = { ...value };
    const recovered = [];
    for (const key in value) {
      const entry = value[key];
      if (typeof entry !== "string")
        continue;
      if (!entry.includes(SPILL_KEY_OPEN) && !entry.includes(SPILL_KEY_CLOSE))
        continue;
      const split = splitSpilledValue(entry);
      if (!split)
        continue;
      out[key] = split.head;
      recovered.push(...split.pairs);
      changed = true;
    }
    if (!changed)
      return { value, changed: false };
    for (const [key, entry] of recovered) {
      if (!(key in out))
        out[key] = entry;
    }
    return { value: out, changed: true };
  }
  var MAX_COERCION_PASSES = 5;
  var MAX_ERROR_ARG_STRING_LENGTH = 256;
  function truncateArgsForError(value) {
    if (typeof value === "string") {
      if (value.length <= MAX_ERROR_ARG_STRING_LENGTH)
        return value;
      return `${value.slice(0, MAX_ERROR_ARG_STRING_LENGTH)}… [truncated ${value.length - MAX_ERROR_ARG_STRING_LENGTH} chars]`;
    }
    if (Array.isArray(value))
      return value.map(truncateArgsForError);
    if (value !== null && typeof value === "object") {
      const out = {};
      for (const [key, entry] of Object.entries(value))
        out[key] = truncateArgsForError(entry);
      return out;
    }
    return value;
  }
  function validateToolArguments(tool, toolCall) {
    const originalArgs = toolCall.arguments;
    if (originalArgs && typeof originalArgs === "object" && "__parseError" in originalArgs) {
      const parseError = originalArgs.__parseError;
      const truncatedRawJson = boundRawToolArguments(String(originalArgs.__rawJson ?? ""));
      throw new ValidationError(`Validation failed for tool "${toolCall.name}": Tool call arguments are not valid JSON.
Parse Error: ${parseError}
Raw JSON:
${truncatedRawJson}`);
    }
    const ctx = getValidationContext(tool);
    const { json } = ctx;
    let normalizedArgs = originalArgs;
    let changed = false;
    const keyNormalization = normalizeDoubleEncodedKeys(normalizedArgs);
    if (keyNormalization.changed) {
      normalizedArgs = keyNormalization.value;
      changed = true;
    }
    const flattenedArgs = normalizeFlattenedArrayProperties(normalizedArgs);
    if (flattenedArgs.changed) {
      normalizedArgs = flattenedArgs.value;
      changed = true;
    }
    const initialNormalization = normalizeOptionalNullsForSchema(json, normalizedArgs);
    if (initialNormalization.changed) {
      normalizedArgs = initialNormalization.value;
      changed = true;
    }
    const enumStringNormalization = normalizeEnumStringWhitespace(json, normalizedArgs);
    if (enumStringNormalization.changed) {
      normalizedArgs = enumStringNormalization.value;
      changed = true;
    }
    const identifierStringNormalization = normalizeIdentifierStringWhitespace(normalizedArgs);
    if (identifierStringNormalization.changed) {
      normalizedArgs = identifierStringNormalization.value;
      changed = true;
    }
    const stringEncodedArrayNorm = normalizeStringEncodedArrayUnions(json, normalizedArgs);
    if (stringEncodedArrayNorm.changed) {
      normalizedArgs = stringEncodedArrayNorm.value;
      changed = true;
    }
    const identifierStringNormalizationAfterArray = normalizeIdentifierStringWhitespace(normalizedArgs);
    if (identifierStringNormalizationAfterArray.changed) {
      normalizedArgs = identifierStringNormalizationAfterArray.value;
      changed = true;
    }
    const singleStringNorm = normalizeSingleStringField(json, normalizedArgs);
    if (singleStringNorm.changed) {
      normalizedArgs = singleStringNorm.value;
      changed = true;
    }
    let result = validateContext(ctx, normalizedArgs);
    if (result.success)
      return result.value;
    const coercionOutcome = runCoercionPasses(ctx, normalizedArgs, result);
    normalizedArgs = coercionOutcome.args;
    changed ||= coercionOutcome.changed;
    result = coercionOutcome.result;
    if (result.success)
      return result.value;
    const spillHeal = healInbandArgSpill(normalizedArgs);
    if (spillHeal.changed) {
      normalizedArgs = spillHeal.value;
      changed = true;
      result = validateContext(ctx, normalizedArgs);
      if (!result.success) {
        const healedOutcome = runCoercionPasses(ctx, normalizedArgs, result);
        normalizedArgs = healedOutcome.args;
        result = healedOutcome.result;
      }
      if (result.success)
        return result.value;
    }
    const errors = result.messages.join(`
`) || "Unknown validation error";
    const receivedArgs = changed ? {
      original: truncateArgsForError(originalArgs),
      normalized: truncateArgsForError(normalizedArgs)
    } : truncateArgsForError(originalArgs);
    const errorMessage = `Validation failed for tool "${toolCall.name}":
${errors}

Received arguments:
${JSON.stringify(receivedArgs, null, 2)}`;
    throw new ValidationError(errorMessage);
  }
  function runCoercionPasses(ctx, args, initial, isRoot = true, insideContent = false) {
    const { json } = ctx;
    const root = ctx.kind === "json" ? ctx.root ?? json : json;
    let normalizedArgs = args;
    let result = initial;
    let changed = false;
    for (let pass = 0;pass < MAX_COERCION_PASSES; pass += 1) {
      if (result.success)
        break;
      const coercion = coerceArgsFromIssues(normalizedArgs, result.flatIssues);
      let passChanged = coercion.changed;
      normalizedArgs = coercion.value;
      const keyNormalizationPass = normalizeDoubleEncodedKeys(normalizedArgs);
      if (keyNormalizationPass.changed) {
        normalizedArgs = keyNormalizationPass.value;
        passChanged = true;
      }
      const speculativeUnion = ctx.kind === "json" && (ctx.speculativeUnion === true || ctx.unionBranches !== undefined && getTagSelectedUnionBranch(ctx.unionBranches, normalizedArgs) !== json);
      const nullNormalization = normalizeOptionalNullsForSchema(json, normalizedArgs, isRoot, root, insideContent, speculativeUnion);
      if (nullNormalization.changed) {
        normalizedArgs = nullNormalization.value;
        passChanged = true;
      }
      const enumStringNormalizationPass = normalizeEnumStringWhitespace(json, normalizedArgs, root);
      if (enumStringNormalizationPass.changed) {
        normalizedArgs = enumStringNormalizationPass.value;
        passChanged = true;
      }
      const identifierStringNormalizationPass = normalizeIdentifierStringWhitespace(normalizedArgs, insideContent);
      if (identifierStringNormalizationPass.changed) {
        normalizedArgs = identifierStringNormalizationPass.value;
        passChanged = true;
      }
      const stringEncodedArrayNormPass = normalizeStringEncodedArrayUnions(json, normalizedArgs);
      if (stringEncodedArrayNormPass.changed) {
        normalizedArgs = stringEncodedArrayNormPass.value;
        passChanged = true;
      }
      const identifierStringNormalizationAfterArrayPass = normalizeIdentifierStringWhitespace(normalizedArgs, insideContent);
      if (identifierStringNormalizationAfterArrayPass.changed) {
        normalizedArgs = identifierStringNormalizationAfterArrayPass.value;
        passChanged = true;
      }
      if (isRoot && !(ctx.kind === "json" && ctx.union)) {
        const singleStringNormPass = normalizeSingleStringField(json, normalizedArgs);
        if (singleStringNormPass.changed) {
          normalizedArgs = singleStringNormPass.value;
          passChanged = true;
        }
      }
      if (!passChanged)
        break;
      changed = true;
      result = validateContext(ctx, normalizedArgs);
    }
    return { args: normalizedArgs, result, changed };
  }

  // ../build/upstream/oh-my-pi/packages/agent/src/tool-arguments.ts
  function validateAgentToolArguments(tool, toolCall, source = "parsed") {
    try {
      return validateToolArguments(tool, toolCall);
    } catch (error) {
      const args = toolCall.arguments;
      if (!tool.lenientArgValidation)
        throw error;
      if (args === null || typeof args !== "object" || Array.isArray(args))
        return args;
      if (source === "parsed" && "__parseError" in args)
        throw error;
      const fallback = { ...args };
      delete fallback.__parseError;
      delete fallback.__rawJson;
      return fallback;
    }
  }

  // ../build/upstream/oh-my-pi/packages/coding-agent/src/tools/think.ts
  var thinkSchema = type({
    thoughts: type("string").describe("private scratchpad; not shown to user"),
    "+": "reject"
  }).describe("private scratchpad; not shown to user");

  class ThinkTool {
    name = "think";
    approval = "read";
    label = "Think";
    summary = "Record private scratchpad thoughts";
    description = "private scratchpad; not shown to user";
    parameters = thinkSchema;
    strict = true;
    intent = "omit";
    async execute(_toolCallId, _params) {
      return {
        content: [
          {
            type: "text",
            text: "------"
          }
        ],
        details: { recorded: true }
      };
    }
  }

  // ../build/upstream/oh-my-pi/packages/coding-agent/src/prompts/tools/todo.md
  var todo_default = `Tasks identified by verbatim content, NEVER generated IDs (task-1). Unique, stable task/phase names; lost text: view, NEVER guess.
Before work, init for 3+ steps, requested task sets, or new instructions. MUST list EVERY user item separately (phased/numbered/bulleted/N); NEVER omit or remember leftovers.
After successful mutation: no active means earliest pending starts (phase order); multiple active means only earliest stays. Blocked NEVER starts automatically; unblock returns pending. Done out of order may rewind pointer but NEVER reopen completed. Mark done immediately; follow phase order.
External waits (user/agent/service): block with optional reason suppresses stop reminder, starts next pending. Unblock when actionable; append a clearing task for agent-actionable blocker.
NEVER call todo alone: init with first work; done/start with next action.
`;

  // ../build/upstream/oh-my-pi/packages/coding-agent/src/tools/todo.ts
  var TodoOp = type('"init" | "start" | "done" | "rm" | "drop" | "block" | "unblock" | "append" | "view"');
  var InitListEntry = type({
    phase: type("string"),
    items: type("string").array().atLeastLength(1)
  });
  var todoSchema = type({
    op: TodoOp,
    "list?": InitListEntry.array().describe("phases for init"),
    "task?": type("string").describe("verbatim task content"),
    "phase?": type("string"),
    "items?": type("string").array().describe("tasks for flat init or append"),
    "reason?": type("string").describe("blocker note for block")
  });
  function findTaskByContent(phases, content) {
    for (const phase of phases) {
      const task = phase.tasks.find((t) => t.content === content);
      if (task)
        return { task, phase };
    }
    return;
  }
  function findPhaseByName(phases, name) {
    return phases.find((phase) => phase.name === name);
  }
  function cloneTask(task) {
    return task.blocker !== undefined ? { content: task.content, status: task.status, blocker: task.blocker } : { content: task.content, status: task.status };
  }
  function clonePhases(phases) {
    return phases.map((phase) => ({ name: phase.name, tasks: phase.tasks.map(cloneTask) }));
  }
  function todoTransitionKey(phase, content) {
    return `${phase}\x00${content}`;
  }
  function getCompletionTransitions(previous, updated) {
    const previousStatuses = new Map;
    for (const phase of previous) {
      for (const task of phase.tasks) {
        previousStatuses.set(todoTransitionKey(phase.name, task.content), task.status);
      }
    }
    const transitions = [];
    for (const phase of updated) {
      for (const task of phase.tasks) {
        if (task.status !== "completed")
          continue;
        const previousStatus = previousStatuses.get(todoTransitionKey(phase.name, task.content));
        if (previousStatus && previousStatus !== "completed") {
          transitions.push({ phase: phase.name, content: task.content });
        }
      }
    }
    return transitions;
  }
  function normalizeInProgressTask(phases) {
    const orderedTasks = phases.flatMap((phase) => phase.tasks);
    if (orderedTasks.length === 0)
      return;
    const inProgressTasks = orderedTasks.filter((task) => task.status === "in_progress");
    if (inProgressTasks.length > 1) {
      for (const task of inProgressTasks.slice(1)) {
        task.status = "pending";
      }
    }
    if (inProgressTasks.length > 0)
      return;
    const firstPendingTask = orderedTasks.find((task) => task.status === "pending");
    if (firstPendingTask)
      firstPendingTask.status = "in_progress";
  }
  function resolveTaskOrError(phases, content, errors) {
    if (!content) {
      errors.push("Missing task content");
      return;
    }
    const hit = findTaskByContent(phases, content);
    if (!hit) {
      if (/^task-\d+$/.test(content)) {
        errors.push(`Task "${content}" not found. Tasks are referenced by content, not by IDs — pass the task's full text from the previous result.`);
      } else {
        const totalTasks = phases.reduce((sum, phase) => sum + phase.tasks.length, 0);
        const hint = totalTasks === 0 ? " (todo list is empty — was it replaced or not yet created?)" : "";
        errors.push(`Task "${content}" not found${hint}`);
      }
    }
    return hit;
  }
  function resolvePhaseOrError(phases, name, errors) {
    if (!name) {
      errors.push("Missing phase name");
      return;
    }
    const phase = findPhaseByName(phases, name);
    if (!phase)
      errors.push(`Phase "${name}" not found`);
    return phase;
  }
  function getTaskTargets(phases, entry, errors) {
    if (entry.task) {
      const hit = resolveTaskOrError(phases, entry.task, errors);
      return hit ? [hit.task] : [];
    }
    if (entry.phase) {
      const phase = resolvePhaseOrError(phases, entry.phase, errors);
      return phase ? [...phase.tasks] : [];
    }
    return phases.flatMap((phase) => phase.tasks);
  }
  var DEFAULT_INIT_PHASE = "Tasks";
  function initPhases(entry, errors) {
    const list = entry.list ?? (entry.items && entry.items.length > 0 ? [{ phase: entry.phase ?? DEFAULT_INIT_PHASE, items: entry.items }] : undefined);
    if (!list) {
      errors.push("Missing list for init operation");
      return [];
    }
    const seenPhases = new Set;
    const seenTasks = new Set;
    for (const listEntry of list) {
      if (seenPhases.has(listEntry.phase)) {
        errors.push(`Duplicate phase "${listEntry.phase}" in init list`);
      }
      seenPhases.add(listEntry.phase);
      for (const content of listEntry.items) {
        if (seenTasks.has(content)) {
          errors.push(`Duplicate task "${content}" in init list`);
        }
        seenTasks.add(content);
      }
    }
    return list.map((listEntry) => ({
      name: listEntry.phase,
      tasks: listEntry.items.map((content) => ({ content, status: "pending" }))
    }));
  }
  function appendItems(phases, entry, errors) {
    if (!entry.phase) {
      errors.push("Missing phase name for append operation");
      return phases;
    }
    if (!entry.items || entry.items.length === 0) {
      errors.push("Missing items for append operation");
      return phases;
    }
    const seen = new Set;
    let hasDuplicate = false;
    for (const content of entry.items) {
      if (seen.has(content) || findTaskByContent(phases, content)) {
        errors.push(`Task "${content}" already exists`);
        hasDuplicate = true;
      }
      seen.add(content);
    }
    if (hasDuplicate)
      return phases;
    let phase = findPhaseByName(phases, entry.phase);
    if (!phase) {
      phase = { name: entry.phase, tasks: [] };
      phases.push(phase);
    }
    for (const content of entry.items) {
      phase.tasks.push({ content, status: "pending" });
    }
    return phases;
  }
  function removeTasks(phases, entry, errors) {
    if (entry.task) {
      const hit = resolveTaskOrError(phases, entry.task, errors);
      if (!hit)
        return phases;
      hit.phase.tasks = hit.phase.tasks.filter((candidate) => candidate !== hit.task);
      return phases;
    }
    if (entry.phase) {
      const phase = resolvePhaseOrError(phases, entry.phase, errors);
      if (!phase)
        return phases;
      phase.tasks = [];
      return phases;
    }
    for (const phase of phases) {
      phase.tasks = [];
    }
    return phases;
  }
  function applyEntry(phases, entry, errors) {
    switch (entry.op) {
      case "init":
        return initPhases(entry, errors);
      case "start": {
        const hit = resolveTaskOrError(phases, entry.task, errors);
        if (!hit)
          return phases;
        for (const phase of phases) {
          for (const candidate of phase.tasks) {
            if (candidate.status === "in_progress" && candidate !== hit.task) {
              candidate.status = "pending";
            }
          }
        }
        hit.task.status = "in_progress";
        return phases;
      }
      case "done": {
        for (const task of getTaskTargets(phases, entry, errors)) {
          task.status = "completed";
        }
        return phases;
      }
      case "drop": {
        for (const task of getTaskTargets(phases, entry, errors)) {
          task.status = "abandoned";
        }
        return phases;
      }
      case "block": {
        if (!entry.task && !entry.phase) {
          errors.push("block requires a task or phase target");
          return phases;
        }
        const reason = entry.reason?.replace(/\s+/g, " ").trim() || undefined;
        for (const task of getTaskTargets(phases, entry, errors)) {
          if (task.status !== "pending" && task.status !== "in_progress" && task.status !== "blocked")
            continue;
          task.status = "blocked";
          task.blocker = reason;
        }
        return phases;
      }
      case "unblock": {
        if (!entry.task && !entry.phase) {
          errors.push("unblock requires a task or phase target");
          return phases;
        }
        for (const task of getTaskTargets(phases, entry, errors)) {
          if (task.status === "blocked") {
            task.status = "pending";
            task.blocker = undefined;
          }
        }
        return phases;
      }
      case "rm":
        return removeTasks(phases, entry, errors);
      case "append":
        return appendItems(phases, entry, errors);
      case "view":
        return phases;
    }
  }
  function inferTodoOp(args, hasExistingPhases) {
    if (Array.isArray(args.list) && args.list.length > 0)
      return "init";
    if (Array.isArray(args.items) && args.items.length > 0) {
      if (typeof args.phase === "string" && args.phase)
        return "append";
      if (!hasExistingPhases)
        return "init";
    }
    return;
  }
  function resolveTodoParams(raw, hasExistingPhases) {
    const direct = todoSchema(raw);
    if (!(direct instanceof type.errors))
      return direct;
    if (isRecord(raw) && raw.op === undefined) {
      const inferred = inferTodoOp(raw, hasExistingPhases);
      if (inferred) {
        const repaired = todoSchema({ ...raw, op: inferred });
        if (!(repaired instanceof type.errors))
          return repaired;
      }
    }
    return `Invalid todo arguments: ${direct.summary}`;
  }
  function applyParams(phases, params) {
    const errors = [];
    const next = applyEntry(phases, params, errors);
    normalizeInProgressTask(next);
    return { phases: next, errors };
  }
  function formatSummary(phases, errors, readOnly = false) {
    const tasks = phases.flatMap((phase) => phase.tasks);
    if (tasks.length === 0) {
      if (errors.length > 0)
        return `Errors: ${errors.join("; ")}`;
      return readOnly ? "Todo list is empty." : "Todo list cleared.";
    }
    const remainingByPhase = phases.map((phase) => ({
      name: phase.name,
      tasks: phase.tasks.filter((task) => task.status === "pending" || task.status === "in_progress")
    })).filter((phase) => phase.tasks.length > 0);
    const remainingTasks = remainingByPhase.flatMap((phase) => phase.tasks.map((task) => ({ ...task, phase: phase.name })));
    let currentIdx = phases.findIndex((phase) => phase.tasks.some((task) => task.status === "pending" || task.status === "in_progress"));
    if (currentIdx === -1)
      currentIdx = phases.length - 1;
    const current = phases[currentIdx];
    const done = current.tasks.filter((task) => task.status === "completed" || task.status === "abandoned").length;
    const lines = [];
    if (errors.length > 0)
      lines.push(`Errors: ${errors.join("; ")}`);
    if (remainingTasks.length === 0) {
      lines.push("Remaining items: none.");
    } else {
      lines.push(`Remaining items (${remainingTasks.length}):`);
      for (const task of remainingTasks) {
        lines.push(`  - ${task.content} [${task.status}] (${task.phase})`);
      }
    }
    const closedAll = tasks.filter((task) => task.status === "completed" || task.status === "abandoned").length;
    const blockedAll = tasks.filter((task) => task.status === "blocked").length;
    const workedAhead = phases.some((phase, idx) => idx > currentIdx && phase.tasks.some((task) => task.status === "completed" || task.status === "abandoned"));
    lines.push(`Overall: ${closedAll}/${tasks.length} done, ${remainingTasks.length} open${blockedAll > 0 ? `, ${blockedAll} blocked` : ""}.`);
    lines.push(`Active phase ${currentIdx + 1}/${phases.length} "${current.name}" (${done}/${current.tasks.length})${workedAhead ? " — earliest phase with open tasks; the in-progress pointer auto-advances to the earliest open task on each completion, so it can sit behind out-of-order work (nothing was un-completed)." : "."}`);
    for (const phase of phases) {
      lines.push(`  ${phase.name}:`);
      for (const task of phase.tasks) {
        const checkbox = task.status === "completed" ? "[X]" : "[ ]";
        const tag = task.status === "in_progress" ? " (in progress)" : task.status === "abandoned" ? " (dropped)" : task.status === "blocked" ? task.blocker ? ` (blocked: ${task.blocker})` : " (blocked)" : "";
        lines.push(`    - ${checkbox} ${task.content}${tag}`);
      }
    }
    return lines.join(`
`);
  }

  class TodoTool {
    session;
    name = "todo";
    approval = "read";
    label = "Todo";
    summary = "Write a structured todo list to track progress within a session";
    description;
    parameters = todoSchema;
    concurrency = "exclusive";
    strict = true;
    lenientArgValidation = true;
    loadMode = "discoverable";
    constructor(session) {
      this.session = session;
      this.description = render(todo_default);
    }
    async execute(_toolCallId, params, _signal, _onUpdate, _context) {
      const previousPhases = clonePhases(this.session.getTodoPhases?.() ?? []);
      const storage = this.session.getSessionFile() ? "session" : "memory";
      const resolved = resolveTodoParams(params, previousPhases.length > 0);
      if (typeof resolved === "string") {
        return {
          content: [{ type: "text", text: resolved }],
          details: { phases: previousPhases, storage },
          isError: true
        };
      }
      const entry = resolved;
      const op = entry.op;
      const readOnly = op === "view";
      const { phases: updated, errors } = readOnly ? { phases: previousPhases, errors: [] } : applyParams(clonePhases(previousPhases), entry);
      const failed = errors.length > 0;
      const effective = failed ? previousPhases : updated;
      const completedTasks = readOnly || failed ? [] : getCompletionTransitions(previousPhases, updated);
      if (!readOnly && !failed)
        this.session.setTodoPhases?.(updated);
      const details = { op, phases: effective, storage };
      if (completedTasks.length > 0)
        details.completedTasks = completedTasks;
      return {
        content: [{ type: "text", text: formatSummary(effective, errors, readOnly) }],
        details,
        isError: errors.length > 0 ? true : undefined
      };
    }
  }

  // ../scripts/omp-core/todo.ts
  function createTodoTool(state, sessionFile) {
    return new TodoTool({
      getSessionFile: () => sessionFile,
      getTodoPhases: () => state.phases,
      setTodoPhases: (phases) => {
        state.phases = phases;
      }
    });
  }

  // ../scripts/omp-core/entry.ts
  var tools = { think: new ThinkTool };
  Object.assign(globalThis, {
    __ompCoreInit(sessionFile) {
      if (tools.todo !== undefined)
        throw new Error("Tool session already initialized");
      const state = { phases: [] };
      tools.todo = createTodoTool(state, sessionFile);
    },
    __ompCoreDescribe(name) {
      if (!Object.hasOwn(tools, name))
        throw new ToolNotFoundError(name);
      const tool = tools[name];
      return { name: tool.name, description: tool.description, parameters: toolWireSchema(tool) };
    },
    async __ompCoreCall(name, params) {
      try {
        if (!Object.hasOwn(tools, name))
          throw new ToolNotFoundError(name);
        const tool = tools[name];
        const call = { type: "toolCall", id: "elixos-tool-call", name, arguments: params };
        const arguments_ = validateAgentToolArguments(tool, call);
        return JSON.stringify({ output: await tool.execute(call.id, arguments_) });
      } catch (error) {
        if (!(error instanceof Error))
          throw error;
        return JSON.stringify({ error: { kind: error.name, message: error.message } });
      }
    }
  });
})();
