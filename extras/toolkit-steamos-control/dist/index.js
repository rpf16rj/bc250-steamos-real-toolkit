const manifest = {"name":"Toolkit SteamOS Control"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const toaster = api.toaster;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

var DefaultContext = {
  color: undefined,
  size: undefined,
  className: undefined,
  style: undefined,
  attr: undefined
};
var IconContext = SP_REACT.createContext && /*#__PURE__*/SP_REACT.createContext(DefaultContext);

var _excluded = ["attr", "size", "title"];
function _objectWithoutProperties(e, t) { if (null == e) return {}; var o, r, i = _objectWithoutPropertiesLoose(e, t); if (Object.getOwnPropertySymbols) { var n = Object.getOwnPropertySymbols(e); for (r = 0; r < n.length; r++) o = n[r], -1 === t.indexOf(o) && {}.propertyIsEnumerable.call(e, o) && (i[o] = e[o]); } return i; }
function _objectWithoutPropertiesLoose(r, e) { if (null == r) return {}; var t = {}; for (var n in r) if ({}.hasOwnProperty.call(r, n)) { if (-1 !== e.indexOf(n)) continue; t[n] = r[n]; } return t; }
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function ownKeys(e, r) { var t = Object.keys(e); if (Object.getOwnPropertySymbols) { var o = Object.getOwnPropertySymbols(e); r && (o = o.filter(function (r) { return Object.getOwnPropertyDescriptor(e, r).enumerable; })), t.push.apply(t, o); } return t; }
function _objectSpread(e) { for (var r = 1; r < arguments.length; r++) { var t = null != arguments[r] ? arguments[r] : {}; r % 2 ? ownKeys(Object(t), true).forEach(function (r) { _defineProperty(e, r, t[r]); }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function (r) { Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r)); }); } return e; }
function _defineProperty(e, r, t) { return (r = _toPropertyKey(r)) in e ? Object.defineProperty(e, r, { value: t, enumerable: true, configurable: true, writable: true }) : e[r] = t, e; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == typeof i ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != typeof t || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r); if ("object" != typeof i) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }
function Tree2Element(tree) {
  return tree && tree.map((node, i) => /*#__PURE__*/SP_REACT.createElement(node.tag, _objectSpread({
    key: i
  }, node.attr), Tree2Element(node.child)));
}
function GenIcon(data) {
  return props => /*#__PURE__*/SP_REACT.createElement(IconBase, _extends({
    attr: _objectSpread({}, data.attr)
  }, props), Tree2Element(data.child));
}
function IconBase(props) {
  var elem = conf => {
    var attr = props.attr,
      size = props.size,
      title = props.title,
      svgProps = _objectWithoutProperties(props, _excluded);
    var computedSize = size || conf.size || "1em";
    var className;
    if (conf.className) className = conf.className;
    if (props.className) className = (className ? className + " " : "") + props.className;
    return /*#__PURE__*/SP_REACT.createElement("svg", _extends({
      stroke: "currentColor",
      fill: "currentColor",
      strokeWidth: "0"
    }, conf.attr, attr, svgProps, {
      className: className,
      style: _objectSpread(_objectSpread({
        color: props.color || conf.color
      }, conf.style), props.style),
      height: computedSize,
      width: computedSize,
      xmlns: "http://www.w3.org/2000/svg"
    }), title && /*#__PURE__*/SP_REACT.createElement("title", null, title), props.children);
  };
  return IconContext !== undefined ? /*#__PURE__*/SP_REACT.createElement(IconContext.Consumer, null, conf => elem(conf)) : elem(DefaultContext);
}

// THIS FILE IS AUTO GENERATED
function FaFan (props) {
  return GenIcon({"attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M352.57 128c-28.09 0-54.09 4.52-77.06 12.86l12.41-123.11C289 7.31 279.81-1.18 269.33.13 189.63 10.13 128 77.64 128 159.43c0 28.09 4.52 54.09 12.86 77.06L17.75 224.08C7.31 223-1.18 232.19.13 242.67c10 79.7 77.51 141.33 159.3 141.33 28.09 0 54.09-4.52 77.06-12.86l-12.41 123.11c-1.05 10.43 8.11 18.93 18.59 17.62 79.7-10 141.33-77.51 141.33-159.3 0-28.09-4.52-54.09-12.86-77.06l123.11 12.41c10.44 1.05 18.93-8.11 17.62-18.59-10-79.7-77.51-141.33-159.3-141.33zM256 288a32 32 0 1 1 32-32 32 32 0 0 1-32 32z"},"child":[]}]})(props);
}

const getStatus = callable("get_status");
const setFanMode = callable("set_fan_mode");
const saveProfile = callable("save_profile");
const selectProfile = callable("select_profile");
const deleteProfile = callable("delete_profile");
const setLedEffects = callable("set_led_effects");
const RuntimeScrollPanel = DFL.ScrollPanel;
function errorText(error) {
    return error instanceof Error ? error.message : String(error);
}
function ControlPanel() {
    const [status, setStatus] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [manualSpeed, setManualSpeed] = SP_REACT.useState(50);
    const manualDirty = SP_REACT.useRef(false);
    const curveDirty = SP_REACT.useRef(false);
    const [activeTab, setActiveTab] = SP_REACT.useState("cooler");
    const [profileName, setProfileName] = SP_REACT.useState("My Profile");
    const [curve, setCurve] = SP_REACT.useState([[45, 30], [60, 55], [75, 85], [90, 100]]);
    const refresh = async () => {
        try {
            const next = await getStatus();
            setStatus(next);
            if (!manualDirty.current)
                setManualSpeed(next.fan.config.manual_percent);
            const selected = next.fan.config.profiles[next.fan.config.active_profile];
            if (!curveDirty.current && selected)
                setCurve(selected.slice(0, 4));
        }
        catch (error) {
            toaster.toast({ title: "Toolkit SteamOS Control", body: errorText(error) });
        }
    };
    SP_REACT.useEffect(() => {
        void refresh();
        const id = window.setInterval(() => void refresh(), 3000);
        return () => window.clearInterval(id);
    }, []);
    const mutate = async (label, action) => {
        if (busy)
            return;
        setBusy(true);
        try {
            const next = await action();
            setStatus(next);
            manualDirty.current = false;
            curveDirty.current = false;
            setManualSpeed(next.fan.config.manual_percent);
            const selected = next.fan.config.profiles[next.fan.config.active_profile];
            if (selected)
                setCurve(selected.slice(0, 4));
            toaster.toast({ title: "Toolkit SteamOS Control", body: label });
        }
        catch (error) {
            toaster.toast({ title: "Action failed", body: errorText(error) });
        }
        finally {
            setBusy(false);
        }
    };
    if (!status) {
        return SP_JSX.jsx(DFL.PanelSection, { title: "Toolkit SteamOS Control", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: "Loading controls\u2026" }) });
    }
    const { fan, led } = status;
    const fanUnavailableMessage = "Pump Fan sensor/PWM control was not detected. Install the NCT6687 PWM driver from Toolkit Extras first.";
    const profileOptions = Object.keys(fan.config.profiles).map((name) => ({ label: name, data: name }));
    const modeOptions = [
        { label: "Automatic", data: "automatic" },
        { label: "Manual", data: "manual" },
        { label: "Managed curve", data: "managed" },
    ];
    const setEffect = (key, value) => {
        const next = { ...led.effects, [key]: value };
        void mutate("LED effects updated", () => setLedEffects(next.temperature, next.audio, next.notifications));
    };
    const updatePoint = (index, part, value) => {
        curveDirty.current = true;
        setCurve((previous) => previous.map((point, pointIndex) => pointIndex === index ? (part === 0 ? [value, point[1]] : [point[0], value]) : point));
    };
    return (SP_JSX.jsx(RuntimeScrollPanel, { style: { width: "100%", height: "100%", minHeight: 0 }, children: SP_JSX.jsxs("div", { style: { padding: "0 12px 24px" }, children: [SP_JSX.jsx(DFL.PanelSection, { children: SP_JSX.jsxs(DFL.PanelSectionRow, { children: [SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: activeTab === "cooler", onClick: () => setActiveTab("cooler"), children: "Cooler" }), led.available && SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: activeTab === "led", onClick: () => setActiveTab("led"), children: "LED bar" })] }) }), activeTab === "cooler" ? SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "Pump Fan status", children: [SP_JSX.jsxs(DFL.PanelSectionRow, { children: ["Hottest CPU / GPU sensor: ", fan.temperature === null ? "Unavailable" : `${fan.temperature} °C`] }), SP_JSX.jsxs(DFL.PanelSectionRow, { children: ["Fan mode: ", fan.config.mode === "managed" ? `Managed · ${fan.config.active_profile}` : fan.config.mode] }), SP_JSX.jsxs(DFL.PanelSectionRow, { children: ["Managed fan service: ", fan.service.active] }), fan.device ? SP_JSX.jsxs(DFL.PanelSectionRow, { children: [fan.device.device, " \u00B7 Pump Fan: ", fan.device.rpm, " RPM \u00B7 ", fan.device.percent, "% \u00B7 control ", fan.device.enable] }) : SP_JSX.jsx(DFL.PanelSectionRow, { children: fanUnavailableMessage })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Fan mode", children: [SP_JSX.jsx(DFL.DropdownItem, { label: "Control mode", description: "Automatic returns control to firmware. Managed uses the hottest CPU or GPU temperature.", rgOptions: modeOptions, selectedOption: fan.config.mode, disabled: busy || !fan.available, onChange: (option) => void mutate("Fan mode updated", () => setFanMode(option.data, manualSpeed)) }), fan.config.mode === "manual" && SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("div", { style: { paddingRight: 16 }, children: SP_JSX.jsx(DFL.SliderField, { label: "Manual fan speed (%)", value: manualSpeed, min: 0, max: 100, step: 1, showValue: true, disabled: busy || !fan.available, onChange: (value) => { manualDirty.current = true; setManualSpeed(value); } }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy || !fan.available, onClick: () => void mutate("Manual fan speed applied", () => setFanMode("manual", manualSpeed)), children: "Apply manual speed" }) })] })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Managed fan profile", children: [SP_JSX.jsx(DFL.DropdownItem, { label: "Active profile", rgOptions: profileOptions, selectedOption: fan.config.active_profile, disabled: busy || !fan.available, onChange: (option) => { const name = option.data; curveDirty.current = false; setProfileName(name); setCurve(fan.config.profiles[name].slice(0, 4)); void mutate("Fan profile selected", () => selectProfile(name)); } }), SP_JSX.jsx(DFL.TextField, { label: "Save profile as", value: profileName, disabled: busy || !fan.available, onChange: (event) => setProfileName(event.target.value) }), curve.map((point, index) => SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs("div", { style: { width: "100%" }, children: [SP_JSX.jsx(DFL.SliderField, { label: `Point ${index + 1} temperature (°C)`, value: point[0], min: 30, max: 100, step: 1, showValue: true, disabled: busy || !fan.available, onChange: (value) => updatePoint(index, 0, value) }), SP_JSX.jsx(DFL.SliderField, { label: `Point ${index + 1} fan speed (%)`, value: point[1], min: 0, max: 100, step: 1, showValue: true, disabled: busy || !fan.available, onChange: (value) => updatePoint(index, 1, value) })] }) }, index)), SP_JSX.jsxs(DFL.PanelSectionRow, { children: [SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy || !fan.available, onClick: () => void mutate("Fan profile saved", () => saveProfile(profileName, curve)), children: "Save and activate profile" }), SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy || !fan.available || ["Quiet", "Balanced", "Performance"].includes(fan.config.active_profile), onClick: () => void mutate("Fan profile deleted", () => deleteProfile(fan.config.active_profile)), children: "Delete active custom profile" })] })] })] }) : led.available && SP_JSX.jsxs(DFL.PanelSection, { title: "LED bar", children: [SP_JSX.jsxs(DFL.PanelSectionRow, { children: ["LED service: ", led.available ? led.service.active : "Not found"] }), SP_JSX.jsx(DFL.ToggleField, { label: "Temperature effect", description: "Shows a warm-to-hot color from the highest CPU or GPU temperature.", checked: led.effects.temperature, disabled: busy || !led.available, onChange: (value) => setEffect("temperature", value) }), SP_JSX.jsx(DFL.ToggleField, { label: "Audio VU effect", description: "Displays system audio level as a live VU meter.", checked: led.effects.audio, disabled: busy || !led.available, onChange: (value) => setEffect("audio", value) }), SP_JSX.jsx(DFL.ToggleField, { label: "Steam notifications", description: "Flashes achievements and notification events.", checked: led.effects.notifications, disabled: busy || !led.available, onChange: (value) => setEffect("notifications", value) })] }), SP_JSX.jsx(DFL.PanelSection, { children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => void refresh(), children: "Refresh status" }) }) })] }) }));
}
var index = definePlugin(() => ({
    name: "Toolkit SteamOS Control",
    titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: "Toolkit SteamOS Control" }),
    content: SP_JSX.jsx(ControlPanel, {}),
    icon: SP_JSX.jsx(FaFan, {}),
    onDismount() { },
}));

index;
//# sourceMappingURL=index.js.map
