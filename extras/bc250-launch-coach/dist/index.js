const manifest = {"name":"BC-250 Launch Coach"};
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

const React = window.SP_REACT;
const DFL = window.DFL;

// Managed presets — tokens are prefixes; each selected prefix is joined and a
// single %command% is appended at the end. "exclusive" options (OptiScaler
// variants) deselect each other inside the group.
const OPTION_GROUPS = [
    { title: "Upscaler / OptiScaler variant (pick one)", exclusive: true, options: [
        { id: "freefg-all", label: "FreeFG all-in-one", prefix: "PROTON_USE_OPTISCALER=freefg-all", desc: "All 5 upscalers — pick in-game via the OptiScaler menu" },
        { id: "freefg-hlxfsr4", label: "FreeFG + HLX FSR 4", prefix: "PROTON_USE_OPTISCALER=freefg-hlxfsr4", desc: "FreeFG 1.4.0 FG + HLX FSR 4 (HelixSR 3.3.0, native Vulkan) — FG ships off" },
        { id: "freefg-hlxdlss", label: "FreeFG + HLX DLSS", prefix: "PROTON_USE_OPTISCALER=freefg-hlxdlss", desc: "FreeFG FG + HLX DLSS (Model E) upscaler" },
        { id: "freefg", label: "FreeFG + FSR4 RC12", prefix: "PROTON_USE_OPTISCALER=freefg", desc: "FreeFG FG + FSR4 RC12 upscaler" },
        { id: "freefg-hlxdlssk", label: "FreeFG + HLX DLSS Preset K", prefix: "PROTON_USE_OPTISCALER=freefg-hlxdlssk", desc: "Preset K — sharper, slower, can sparkle on foliage" },
        { id: "freefg-hlxfsr4full", label: "FreeFG + HLX FSR 4 Full", prefix: "PROTON_USE_OPTISCALER=freefg-hlxfsr4full", desc: "Full FSR 4.1.2 network — sharper, slower" },
        { id: "off", label: "No upscaling", prefix: "PROTON_USE_OPTISCALER=off", desc: "The game as it ships — no OptiScaler/FSR4" }
    ]},
    { title: "Extra options", exclusive: false, options: [
        { id: "directmesh", label: "DirectMesh shaders", prefix: "RADV_DIRECTMESH=1", desc: "v1.4 mesh/task shaders incl. Task+Mesh pipelines, barycentrics, DGC" },
        { id: "fsr4debug", label: "FSR4 debug watermark", prefix: "BC250_FSR4_DEBUG=1", desc: "Watermark + OptiScaler overlay log" },
        { id: "nofsr4", label: "Disable FSR4 upgrade", prefix: "PROTON_FSR4_UPGRADE=0", desc: "Turn off FSR4 upscaling for this game" },
        { id: "anticheat", label: "Ignore anti-cheat block", prefix: "BC250_FSR4_IGNORE_ANTICHEAT=1", desc: "Keep FSR4/OptiScaler on EAC/BattlEye games (ban risk!)" },
        { id: "winmmfix", label: "winmm.dll conflict fix", prefix: "PROTON_OPTISCALER_NAME=dxgi.dll", desc: "For games shipping their own winmm.dll" },
        { id: "optiscalermenu", label: "Re-show upscaler menu", prefix: "PROTON_OPTISCALER_MENU=1", desc: "One-shot: re-shows the GTK menu next launch — remove after" }
    ]},
    { title: "DLSS / FrameGen (pick one — they share BC250_OPTISCALER_EXTRA)", exclusive: true, options: [
        { id: "spoofdxgi", label: "DLSS + Reflex spoof", prefix: 'BC250_OPTISCALER_EXTRA="Spoofing.Dxgi=true"', desc: "Game offers DLSS/Reflex, OptiScaler translates to FSR4" },
        { id: "spoofreg", label: "DLSS + Registry spoof", prefix: 'BC250_OPTISCALER_EXTRA="Spoofing.Dxgi=true;Spoofing.Registry=true"', desc: "Add registry spoof if the game warns about GPU/driver" },
        { id: "fgenable", label: "Frame generation ON", prefix: 'BC250_OPTISCALER_EXTRA="FrameGen.Enabled=true"', desc: "FreeFG ships OFF by default — force it on" },
        { id: "dlssg", label: "Game's DLSS FG → XeFG", prefix: 'BC250_OPTISCALER_EXTRA="Spoofing.Dxgi=true;FrameGen.Enabled=true"', desc: "Game's own DLSS FG feeds FreeFG XeFG (needs spoofing)" }
    ]}
];

const ALL_OPTIONS = OPTION_GROUPS.flatMap(function(g) { return g.options; });
const MANAGED_PREFIXES = ALL_OPTIONS.map(function(o) { return o.prefix.split("=")[0] + "="; });

var state = {};          // appid -> {options: string} or {dismissed: true}
var lastLaunchAppId = 0;
var pendingAppIds = {};  // appids with a modal currently open

function gameName(appid) {
    try {
        var s = window.appStore;
        var ov = s && (s.GetAppOverviewById || s.GetAppOverviewByAppID) &&
            (s.GetAppOverviewById || s.GetAppOverviewByAppID).call(s, appid);
        return (ov && ov.display_name) || ("App " + appid);
    } catch (e) {
        return "App " + appid;
    }
}

async function getLaunchOptions(appid) {
    try {
        var res = await window.SteamClient.Apps.GetLaunchOptionsForApp(appid);
        if (typeof res === "string") return res;
        if (res && typeof res.strLaunchOptions === "string") return res.strLaunchOptions;
    } catch (e) {}
    return "";
}

// Remove our managed tokens and the %command% placeholder so user-authored
// options survive a reconfigure.
function stripManaged(str) {
    return (str || "").split(/\s+/).filter(function(tok) {
        if (!tok || tok === "%command%") return false;
        for (var i = 0; i < MANAGED_PREFIXES.length; i++) {
            if (tok.indexOf(MANAGED_PREFIXES[i]) === 0) return false;
        }
        return true;
    }).join(" ");
}

function buildOptionsString(existing, selectedIds) {
    var kept = stripManaged(existing);
    var chosen = [];
    ALL_OPTIONS.forEach(function(o) {
        if (selectedIds.indexOf(o.id) !== -1) chosen.push(o.prefix);
    });
    var parts = kept ? [kept] : [];
    if (chosen.length) parts.push(chosen.join(" "));
    parts.push("%command%");
    return parts.join(" ");
}

// Old upstream variant names → current preset ids (upstream auto-aliases
// these at launch; mirror it so saved configs still show a selection).
var VARIANT_ALIASES = {
    "PROTON_USE_OPTISCALER=helixsr": "freefg-hlxdlss",
    "PROTON_USE_OPTISCALER=helixsr-ffx": "freefg-hlxdlss",
    "PROTON_USE_OPTISCALER=freefg-helixsr": "freefg-hlxdlss",
    "PROTON_USE_OPTISCALER=hlxfsr4": "freefg-hlxfsr4",
    "PROTON_USE_OPTISCALER=fsr411f": "freefg",
    "PROTON_USE_OPTISCALER=fsr412f": "freefg",
    "PROTON_USE_OPTISCALER=signed": "freefg"
};

function initialSelection(existing) {
    // Whole-token compare — substring matching would double-select
    // ("freefg" is a prefix of "freefg-hlxfsr4" etc. — exact tokens only).
    var toks = (existing || "").split(/\s+/);
    var sel = [];
    ALL_OPTIONS.forEach(function(o) {
        if (toks.indexOf(o.prefix) !== -1) sel.push(o.id);
    });
    toks.forEach(function(t) {
        var mapped = VARIANT_ALIASES[t];
        if (mapped && sel.indexOf(mapped) === -1) sel.push(mapped);
    });
    return sel;
}

var panelRefresh = null;
function refreshPanel() { if (panelRefresh) panelRefresh(); }

async function applyAndSave(appid, optionsStr) {
    try {
        await window.SteamClient.Apps.SetAppLaunchOptions(appid, optionsStr);
    } catch (e) {
        toaster.toast({ title: "BC-250 Launch Coach", body: "Failed to write launch options: " + e });
        return false;
    }
    try {
        await api.call("save_app", appid, optionsStr);
    } catch (e) {
        toaster.toast({ title: "BC-250 Launch Coach",
            body: "Options applied, but saving failed — the dialog may reappear next launch." });
    }
    state[String(appid)] = { options: optionsStr };
    refreshPanel();
    return true;
}

async function restartGame(appid) {
    try {
        if (window.SteamClient.Apps.TerminateApp) {
            await window.SteamClient.Apps.TerminateApp(appid);
        }
        await new Promise(function(r) { setTimeout(r, 1200); });
        await window.SteamClient.Apps.RunGame(appid, "", -1, 100);
        return true;
    } catch (e) {
        return false;
    }
}

function OptionsModal(props) {
    var appid = props.appid;
    var sel0 = props.initialSelected || [];
    var st = React.useState(sel0);
    var selected = st[0]; var setSelected = st[1];

    function toggle(opt, group, checked) {
        var next = selected.filter(function(id) { return id !== opt.id; });
        if (checked) {
            if (group.exclusive) {
                var ids = group.options.map(function(o) { return o.id; });
                next = next.filter(function(id) { return ids.indexOf(id) === -1; });
            }
            next.push(opt.id);
        }
        setSelected(next);
    }

    async function save(restart) {
        var optsStr = buildOptionsString(props.existing, selected);
        if (!await applyAndSave(appid, optsStr)) { props.closeModal(); return; }
        props.closeModal();
        if (restart) {
            var ok = await restartGame(appid);
            toaster.toast({
                title: "BC-250 Launch Coach",
                body: ok ? "Options applied — restarting " + props.name + "…"
                         : "Options applied. Close and relaunch " + props.name + " to apply."
            });
        } else {
            toaster.toast({ title: "BC-250 Launch Coach", body: "Options applied to " + props.name });
        }
    }

    var groups = OPTION_GROUPS.map(function(group, gi) {
        return SP_JSX.jsxs(DFL.PanelSection, {
            title: group.title,
            children: group.options.map(function(opt) {
                return SP_JSX.jsx(DFL.ToggleField, {
                    label: opt.label,
                    description: opt.desc,
                    checked: selected.indexOf(opt.id) !== -1,
                    onChange: function(c) { toggle(opt, group, c); }
                }, opt.id);
            })
        }, "g" + gi);
    });

    var buttons = [
        SP_JSX.jsx(DFL.DialogButton, {
            onClick: function() { save(true); },
            children: "Save & Restart"
        }, "sr"),
        SP_JSX.jsx(DFL.DialogButton, {
            onClick: function() { save(false); },
            children: "Save"
        }, "s")
    ];
    if (!props.hasSaved) {
        buttons.push(SP_JSX.jsx(DFL.DialogButton, {
            onClick: async function() {
                try { await api.call("dismiss_app", appid); } catch (e) {}
                state[String(appid)] = { dismissed: true };
                refreshPanel();
                props.closeModal();
            },
            children: "Don't ask for this game"
        }, "d"));
    }
    groups.push(SP_JSX.jsxs("div", { style: { display: "flex", gap: "8px", marginTop: "12px", flexWrap: "wrap" }, children: buttons }, "btns"));

    return SP_JSX.jsx(DFL.ModalRoot, {
        onCancel: props.closeModal,
        closeModal: props.closeModal,
        children: SP_JSX.jsxs("div", {
            style: { padding: "0 12px 12px", minWidth: "480px" },
            children: [
                SP_JSX.jsx("div", { style: { fontWeight: "bold", fontSize: "16px", margin: "8px 0" },
                    children: "BC-250 Proton options — " + props.name }, "h"),
                SP_JSX.jsx("div", { style: { fontSize: "12px", color: "#999", marginBottom: "8px" },
                    children: "Applied as Steam launch options (Properties → Launch Options). Asked once per game." }, "sub")
            ].concat(groups)
        })
    });
}

function openCoachDialog(appid) {
    if (!DFL || !DFL.showModal || !window.SteamClient) {
        toaster.toast({ title: "BC-250 Launch Coach", body: "Steam UI internals unavailable — set launch options manually." });
        return;
    }
    if (pendingAppIds[appid]) return;
    pendingAppIds[appid] = true;
    // External closes (route change, Steam-side dismiss) may never reach our
    // closeModal — re-arm the prompt after a long timeout so the appid isn't
    // stuck silenced until a Decky reload.
    setTimeout(function() { delete pendingAppIds[appid]; }, 5 * 60 * 1000);
    getLaunchOptions(appid).then(function(existing) {
        var saved = state[String(appid)];
        var initial = saved && saved.options ? initialSelection(saved.options) : initialSelection(existing);
        var modal;
        function close() {
            delete pendingAppIds[appid];
            if (modal && modal.Close) modal.Close();
        }
        modal = DFL.showModal(SP_JSX.jsx(OptionsModal, {
            appid: appid,
            name: gameName(appid),
            existing: existing,
            hasSaved: !!(saved && saved.options),
            initialSelected: initial,
            closeModal: close
        }));
    }).catch(function() { delete pendingAppIds[appid]; });
}

var stateLoaded = false;
var queuedAppIds = [];

function onLifetime(update) {
    var appid = update && (update.unAppID || update.appid);
    if (!appid || !update.bRunning) return;
    lastLaunchAppId = appid;
    refreshPanel();
    if (!stateLoaded) {                        // backend config still loading
        if (queuedAppIds.indexOf(appid) === -1) queuedAppIds.push(appid);
        return;
    }
    if (state[String(appid)]) return;          // configured or dismissed — silent
    openCoachDialog(appid);
}

function flushQueued() {
    queuedAppIds.forEach(function(appid) {
        if (!state[String(appid)]) openCoachDialog(appid);
    });
    queuedAppIds = [];
}

// Re-run safety: a hot reload would double-register the lifetime listener.
if (window.__bc250LaunchCoachCleanup) {
    try { window.__bc250LaunchCoachCleanup(); } catch (e) {}
}

var ControlPanel = function() {
    var force = React.useReducer(function(x) { return x + 1; }, 0);
    var refresh = function() { force[1](); };
    React.useEffect(function() {
        panelRefresh = force[1];
        return function() { if (panelRefresh === force[1]) panelRefresh = null; };
    }, []);

    var entries = Object.keys(state).map(function(appid) {
        var entry = state[appid];
        return SP_JSX.jsxs(DFL.PanelSectionRow, { children: [
            SP_JSX.jsx("div", { style: { fontWeight: "bold" }, children: gameName(Number(appid)) }),
            SP_JSX.jsx("div", { style: { fontSize: "11px", color: "#999", fontFamily: "monospace", wordBreak: "break-all" },
                children: entry.dismissed ? "(never ask)" : entry.options }),
            !entry.dismissed && SP_JSX.jsx(DFL.ButtonItem, {
                layout: "below", children: "Reconfigure",
                onClick: function() { openCoachDialog(Number(appid)); }
            }),
            SP_JSX.jsx(DFL.ButtonItem, {
                layout: "below", children: "Forget",
                onClick: async function() {
                    await api.call("remove_app", appid);
                    delete state[appid];
                    refresh();
                }
            })
        ] }, appid);
    });

    return SP_JSX.jsxs("div", { children: [
        !!lastLaunchAppId && SP_JSX.jsx(DFL.PanelSection, {
            title: "Current / last launched game",
            children: SP_JSX.jsx(DFL.PanelSectionRow, {
                children: SP_JSX.jsx(DFL.ButtonItem, {
                    layout: "below",
                    children: "Configure " + gameName(lastLaunchAppId),
                    onClick: function() { openCoachDialog(lastLaunchAppId); }
                })
            })
        }),
        SP_JSX.jsx(DFL.PanelSection, {
            title: "Configured games",
            children: entries.length ? SP_JSX.jsx("div", { children: entries })
                : SP_JSX.jsx(DFL.PanelSectionRow, {
                    children: SP_JSX.jsx("div", { style: { fontSize: "12px", color: "#999" },
                        children: "Nothing yet — launch a game and the dialog will appear." })
                })
        })
    ] });
};

var index = definePlugin(function() {
    // definePlugin must return the plugin object synchronously — load config
    // in the background and queue any launches that arrive meanwhile.
    api.call("get_state").then(function(s) {
        state = s || {};
        stateLoaded = true;
        flushQueued();
        refreshPanel();
    }).catch(function() { stateLoaded = true; flushQueued(); });

    var unregister = null;
    if (window.SteamClient && SteamClient.GameSessions && SteamClient.GameSessions.RegisterForAppLifetimeNotifications) {
        unregister = SteamClient.GameSessions.RegisterForAppLifetimeNotifications(onLifetime);
    } else {
        toaster.toast({ title: "BC-250 Launch Coach", body: "GameSessions API not found — launch prompts disabled, configure via this panel." });
    }

    window.__bc250LaunchCoachCleanup = function() {
        if (unregister && unregister.unregister) unregister.unregister();
        else if (typeof unregister === "function") unregister();
    };

    return {
        name: "BC-250 Launch Coach",
        titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: "BC-250 Launch Coach" }),
        content: SP_JSX.jsx(ControlPanel, {}),
        icon: SP_JSX.jsx("svg", { viewBox: "0 0 24 24", width: "1em", height: "1em", fill: "currentColor", children: SP_JSX.jsx("path", {
            d: "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"
        }) }),
        alwaysRenderTitle: true,
        onDismount: function() {
            if (window.__bc250LaunchCoachCleanup) {
                try { window.__bc250LaunchCoachCleanup(); } catch (e) {}
            }
        }
    };
});

index;
