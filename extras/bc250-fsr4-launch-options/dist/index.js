const manifest = {"name":"BC-250 FSR4 Launch Options"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
} catch (e) {
    api = internalAPIConnection.connect(1, manifest.name);
}
const toaster = api.toaster;
const definePlugin = function(fn) { return function() { return fn(); }; };

var LAUNCH_OPTIONS = [
    { label: "Disable FSR4 upgrade", cmd: "PROTON_FSR4_UPGRADE=0 %command%", desc: "Turn off FSR4 upscaling for this game" },
    { label: "FSR4 debug watermark", cmd: "BC250_FSR4_DEBUG=1 %command%", desc: "Show FSR4 watermark + OptiScaler overlay log" },
    { label: "Mesh/task shaders", cmd: "RADV_GFX103=1 %command%", desc: "Enable mesh/task shaders on RADV" },
    { label: "fsr411f RC11 (default)", cmd: 'PROTON_USE_OPTISCALER=fsr411f %command%', desc: "BC-250 fork bridge RC11 — already the default, set only to pin it" },
    { label: "Use AMD signed FSR4", cmd: 'PROTON_USE_OPTISCALER=signed %command%', desc: "AMD's signed 4.0.2 bridge" },
    { label: "Use fsr411b", cmd: 'PROTON_USE_OPTISCALER=fsr411b %command%', desc: "Third-party 4.1.1b, RDNA2 ghosting fix" },
    { label: "Use fsr411rc9", cmd: 'PROTON_USE_OPTISCALER=fsr411rc9 %command%', desc: "Older BC-250 fork bridge RC9" },
    { label: "Use fsr411rc10", cmd: 'PROTON_USE_OPTISCALER=fsr411rc10 %command%', desc: "Older BC-250 fork bridge RC10" },
    { label: "Fix winmm.dll conflict", cmd: 'PROTON_OPTISCALER_NAME=dxgi.dll %command%', desc: "For games shipping own winmm.dll" },
    { label: "DLSS + Reflex spoof", cmd: 'BC250_OPTISCALER_EXTRA="Spoofing.Dxgi=true" %command%', desc: "Makes game offer DLSS/Reflex, OptiScaler translates to FSR4" },
    { label: "DLSS + Registry spoof", cmd: 'BC250_OPTISCALER_EXTRA="Spoofing.Dxgi=true;Spoofing.Registry=true" %command%', desc: "Add registry spoof if game warns about GPU/driver" }
];

function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function() {
            toaster.toast({ title: "BC-250 FSR4", body: "Copied to clipboard" });
        }).catch(function() {
            fallbackCopy(text);
        });
    } else {
        fallbackCopy(text);
    }
}

function fallbackCopy(text) {
    var el = document.createElement("textarea");
    el.value = text;
    el.style.position = "fixed";
    el.style.opacity = "0";
    document.body.appendChild(el);
    el.select();
    try {
        document.execCommand("copy");
        toaster.toast({ title: "BC-250 FSR4", body: "Copied to clipboard" });
    } catch (e) {
        toaster.toast({ title: "BC-250 FSR4", body: "Copy failed, copy manually" });
    }
    document.body.removeChild(el);
}

function renderOption(opt) {
    return SP_JSX.jsx(DFL.PanelSectionRow, {
        children: SP_JSX.jsxs("div", {
            style: { display: "flex", flexDirection: "column", gap: "4px", marginBottom: "8px" },
            children: [
                SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: function() { copyToClipboard(opt.cmd); }, children: opt.label }),
                SP_JSX.jsx("div", { style: { fontSize: "12px", color: "#999", paddingLeft: "4px", fontFamily: "monospace" }, children: opt.cmd }),
                SP_JSX.jsx("div", { style: { fontSize: "11px", color: "#666", paddingLeft: "4px" }, children: opt.desc })
            ]
        })
    });
}

function Fsr4Icon() {
    return SP_JSX.jsx("svg", {
        viewBox: "0 0 24 24",
        width: "1em",
        height: "1em",
        fill: "currentColor",
        children: SP_JSX.jsx("path", {
            d: "M12 2L4 7v10l8 5 8-5V7l-8-5zm0 2.2L18 8v8l-6 3.8L6 16V8l6-3.8zM8 9v6h2v-4l4 4h2V9h-2v4l-4-4H8z"
        })
    });
}

function ControlPanel() {
    var optionRows = LAUNCH_OPTIONS.map(function(opt) { return renderOption(opt); });
    return SP_JSX.jsx("div", {
        style: { padding: "0 12px 24px" },
        children: [
            SP_JSX.jsx(DFL.PanelSection, {
                title: "Launch Options",
                children: [
                    SP_JSX.jsx(DFL.PanelSectionRow, {
                        children: SP_JSX.jsx("div", {
                            style: { fontSize: "13px", color: "#999", marginBottom: "8px" },
                            children: "Tap a button to copy, paste into Steam Properties Launch Options"
                        })
                    })
                ].concat(optionRows)
            }),
            SP_JSX.jsx(DFL.PanelSection, {
                title: "Notes",
                children: SP_JSX.jsx(DFL.PanelSectionRow, {
                    children: SP_JSX.jsx("div", {
                        style: { fontSize: "12px", color: "#999", lineHeight: "1.5" },
                        children: "FSR4 and OptiScaler are ON by default (fsr411f RC11). FSR4/OptiScaler auto-disable on EAC/BattlEye detection. Do NOT use PROTON_DLSS_UPGRADE or PROTON_XESS_UPGRADE, they will prevent the game from starting."
                    })
                })
            })
        ]
    });
}

var index = definePlugin(function() {
    return {
        name: "BC-250 FSR4 Launch Options",
        titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: "BC-250 FSR4 Launch Options" }),
        content: SP_JSX.jsx(ControlPanel, {}),
        icon: SP_JSX.jsx(Fsr4Icon, {}),
        onDismount: function() {}
    };
});

index;
