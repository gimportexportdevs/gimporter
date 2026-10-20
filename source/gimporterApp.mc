import Toybox.Lang;

using Toybox.Application as App;
using Toybox.Application.Storage;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;
using Toybox.Position;
using Toybox.Timer as TIME;
using Toybox.Time;
using Toybox.System as System;
using Toybox.Graphics as GFX;

function getApp() as gimporterApp {
    return App.getApp() as gimporterApp;
}

// (:glance): referenced by gimporterApp's field initializers, which run in
// the glance scope as well.
(:glance)
const DEFAULT_PORT = 22222;

// What the app is doing; gimporterApp.mState. Every asynchronous callback
// (timer, port reply, web response) checks that the app is still in the
// state that started it and ignores itself otherwise, e.g. after the user
// backed out or the phone pushed a track meanwhile.
//
//   IDLE ─start─> WAITING_FOR_PHONE ─> REQUESTING_PORT ─> LOADING_LIST ─> IDLE (track list shown)
//   IDLE ─track chosen─> REQUESTING_PORT ─> DOWNLOADING
//   phone pushes a track ─> DOWNLOADING
//   DOWNLOADING ─> LEAVING (chosen on the watch) | READY_TO_START (pushed)
//                | CHOOSING_SIMILAR | IDLE (failed)
//   CHOOSING_SIMILAR ─> LEAVING
//   location chosen ─> LEAVING, location pushed ─> READY_TO_START
//   READY_TO_START ─start─> LEAVING, ─phone pushes the next one─> DOWNLOADING
//   back ─> IDLE (except while LEAVING)
(:glance)
enum {
    STATE_IDLE,
    STATE_WAITING_FOR_PHONE,  // no Bluetooth, or Wi-Fi on: retried every second
    STATE_REQUESTING_PORT,  // asked gexporter for its port, then mPendingTrackIndex or the list
    STATE_LOADING_LIST,  // dir.json requested
    STATE_DOWNLOADING,  // a track is downloading
    STATE_CHOOSING_SIMILAR,  // the downloaded track was not found, the user picks a similar one
    STATE_READY_TO_START,  // a track or location from the phone is on the watch, start launches it
    STATE_LEAVING  // exitTo() scheduled
}

// The user can start loading the track list.
function canLoadListIn(state as Number) as Boolean {
    return state == STATE_IDLE || state == STATE_WAITING_FOR_PHONE || state == STATE_READY_TO_START;
}

// A track or location pushed by the phone is acted on: it supersedes
// loading the list and the one waiting to be started, but not an import
// the watch is already busy with.
function acceptsPushIn(state as Number) as Boolean {
    return state != STATE_DOWNLOADING && state != STATE_CHOOSING_SIMILAR && state != STATE_LEAVING;
}

// A track is being imported: the phone was told "importing".
function isImportingIn(state as Number) as Boolean {
    return state == STATE_DOWNLOADING || state == STATE_CHOOSING_SIMILAR;
}

// Menu item identifiers indexed by position; shared by TrackChooser and
// SimilarCourseChooser (the old WatchUi.Menu identifies items by Symbol
// and caps at 16 items).
const ITEM_SYMBOLS = [:ITEM_0, :ITEM_1, :ITEM_2, :ITEM_3,
                      :ITEM_4, :ITEM_5, :ITEM_6, :ITEM_7,
                      :ITEM_8, :ITEM_9, :ITEM_10, :ITEM_11,
                      :ITEM_12, :ITEM_13, :ITEM_14, :ITEM_15] as Array<Symbol>;

function itemToSym(i as Number) as Symbol {
    return ITEM_SYMBOLS[i];
}

function symToItem(sym as Symbol) as Number {
    for (var i = 0; i < ITEM_SYMBOLS.size(); i++) {
        if (sym.equals(ITEM_SYMBOLS[i])) {
            return i;
        }
    }
    return 0;
}

// Map Communications error codes the user can act on to specific
// messages; anything else falls through to the caller's default.
function commErrorString(responseCode as Number, def as ResourceId) as ResourceId {
    if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
        return Rez.Strings.BluetoothDisconnected;
    }
    if (responseCode == Comm.STORAGE_FULL) {
        return Rez.Strings.StorageFull;
    }
    if (responseCode == Comm.NETWORK_REQUEST_TIMED_OUT) {
        return Rez.Strings.DownloadTimeout;
    }
    if (responseCode == Comm.NETWORK_RESPONSE_TOO_LARGE) {
        return Rez.Strings.ResponseTooLarge;
    }
    return def;
}

// A dir.json entry for a shared destination (rather than a course) carries
// its coordinates as strings: JSON numbers would arrive as 32-bit floats.
function isLocation(track as Dictionary) as Boolean {
    if (track["lat"] instanceof Toybox.Lang.String && track["lon"] instanceof Toybox.Lang.String) {
        return true;
    }
    return false;
}

// A location pushed by gexporter waits in the mailbox until the app runs;
// one older than this is from an earlier share and must not start a
// navigation out of the blue.
const LOCATION_MESSAGE_MAX_AGE = 900;  // seconds
// Tolerated clock difference between phone and watch.
const LOCATION_MESSAGE_MAX_SKEW = 300;  // seconds

// "time" (the phone's epoch seconds) of a queued phone message is recent
// enough to act on.
function isFreshMessage(data as Dictionary, now as Number) as Boolean {
    var time = data["time"];
    if (!(time instanceof Number)) {
        return false;
    }
    return (now - time) <= LOCATION_MESSAGE_MAX_AGE && (time - now) <= LOCATION_MESSAGE_MAX_SKEW;
}

// A phone message {"type": "location", "title", "lat", "lon", "time"} that
// is recent enough to act on.
function isLocationMessage(data as Object?, now as Number) as Boolean {
    if (!(data instanceof Dictionary)) {
        return false;
    }
    var type = data["type"];
    if (!(type instanceof String) || !type.equals("location")
        || !(data["title"] instanceof String) || !$.isLocation(data)) {
        return false;
    }
    return $.isFreshMessage(data, now);
}

// A phone message {"type": "track", "url", "title", "port", "time"}: the
// phone asks to download a track now. "port" is gexporter's server port,
// so no port handshake is needed.
function isTrackMessage(data as Object?, now as Number) as Boolean {
    if (!(data instanceof Dictionary)) {
        return false;
    }
    var type = data["type"];
    var port = data["port"];
    if (!(type instanceof String) || !type.equals("track")
        || !(data["url"] instanceof String) || !(data["title"] instanceof String)
        || !(port instanceof Number) || port <= 0 || port > 65535) {
        return false;
    }
    return $.isFreshMessage(data, now);
}

// Whether the device has the PersistedContent API to list and delete the
// app's content; chosen per device at build time, see monkey-base.jungleinc.
(:content)
function hasContentApi() as Boolean {
    return true;
}

(:nocontent)
function hasContentApi() as Boolean {
    return false;
}

// Content kinds the phone can list and delete. remove() only works for
// content gimporter created itself, which is what getApp*() returns.
const CONTENT_KINDS = ["course", "track", "route", "waypoint"] as Array<String>;
// Keeps the reply to the phone within the BLE message size.
const MAX_CONTENT_ITEMS = 100;

// Storage key of the {"<kind>:<id>" => fingerprint} map. gexporter sends a
// fingerprint of each track and location (a hash of its content); gimporter
// remembers which content on the watch came from it, so the phone can tell
// what is on the watch even when two tracks share a name.
const FINGERPRINTS = "fingerprints";

function contentKey(kind as String, id as Number) as String {
    return kind + ":" + id;
}

// Append [kind, name, id, fingerprint] for each content object of the
// iterator; the fingerprint is "" for content imported before fingerprints.
function appendContent(items as Array, kind as String, it as PC.Iterator, fingerprints as Dictionary) as Void {
    var c = it.next() as PC.Course?;
    while (c != null && items.size() < MAX_CONTENT_ITEMS) {
        var fp = fingerprints[$.contentKey(kind, c.getId())];
        items.add([kind, c.getName(), c.getId(), fp instanceof String ? fp : ""]);
        c = it.next() as PC.Course?;
    }
}

// The content kind of a PersistedContent object, as used in messages.
// Some devices lack some of the classes at runtime although the compiler
// accepts them (a MARQ crashed on "Could not find symbol 'Track'"), so
// check with "has" before instanceof.
function kindOf(content as PC.Content) as String {
    if ((PC has :Waypoint) && content instanceof PC.Waypoint) {
        return "waypoint";
    }
    if ((PC has :Track) && content instanceof PC.Track) {
        return "track";
    }
    if ((PC has :Route) && content instanceof PC.Route) {
        return "route";
    }
    return "course";
}

function findContentById(it as PC.Iterator, id as Number) as PC.Course? {
    var c = it.next() as PC.Course?;
    while (c != null) {
        if (c.getId() == id) {
            return c;
        }
        c = it.next() as PC.Course?;
    }
    return null;
}

// The [kind, id] pairs of a fresh {"type": "delete", "items", "time"}
// request, or null if it is stale or malformed. A delete queued while the
// app was closed must not run hours later.
function deleteRequestItems(data as Dictionary, now as Number) as Array? {
    var items = data["items"];
    if (!(items instanceof Array) || !$.isFreshMessage(data, now)) {
        return null;
    }
    for (var i = 0; i < items.size(); i++) {
        var item = items[i];
        if (!(item instanceof Array) || item.size() != 2
            || !(item[0] instanceof String) || !(item[1] instanceof Number)) {
            return null;
        }
    }
    return items;
}

// Tells the app's outbox that a message reached the phone or failed, so
// it sends the next one: a transmit() while another one is still on its
// way gets lost (the status right after the content list never arrived).
class OutboxListener extends Comm.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        $.getApp().onTransmitDone(true);
    }

    function onError() as Void {
        System.println("Sending to the phone failed");
        $.getApp().onTransmitDone(false);
    }
}

// The device may shorten long names, so a stored name that is a prefix
// of ours also counts; an exact match wins.
function findWaypoint(it as PC.Iterator, name as String) as PC.Waypoint? {
    var prefixMatch = null;
    var wp = it.next() as PC.Waypoint?;
    while (wp != null) {
        var wpName = wp.getName();
        if (wpName.equals(name)) {
            return wp;
        }
        if (wpName.length() > 0 && name.find(wpName) == 0) {
            prefixMatch = wp;
        }
        wp = it.next() as PC.Waypoint?;
    }
    return prefixMatch;
}

// (:glance) because the system instantiates the AppBase subclass inside the
// glance scope. Methods referencing non-glance classes (views, chooser) stay
// safe there because symbols resolve at call time, and those methods are
// never called while running as a glance.
(:glance)
class gimporterApp extends App.AppBase {
    var mState as Number = STATE_IDLE;  // see the STATE_* enum
    var tracks as Array? = null;
    var trackToStart as String?;  // title of the track or location being imported
    var status as String or ResourceId = "";
    var mGPXorFIT as String;
    var bluetoothTimer as TIME.Timer;
    var exitTimer as TIME.Timer;
    var mIntent as System.Intent? = null;  // for exitTimer
    var mServerPort as Number = DEFAULT_PORT;  // Updated dynamically via the port handshake
    var mPendingTrackIndex as Number? = null;  // REQUESTING_PORT: track to download, null for the list
    var mPortResponseTimer as TIME.Timer?;  // Timer for port response timeout
    var mSimilarCourses as Array? = null;  // CHOOSING_SIMILAR: the courses to choose from
    var mPortFallbackTimer as TIME.Timer?;  // Timer for delayed fallback after BLE disruption
    var mPushedTrack as Dictionary? = null;  // Track the phone asked for, started by mPushTimer
    var mPendingFingerprint as String? = null;  // gexporter's fingerprint of the track being imported
    var mPushTimer as TIME.Timer?;
    var mBackToStart as Boolean = false;  // popping the status views back to the start view
    var mStartViewOnTop as Boolean = true;  // no status view pushed over the start view
    var mStartWhenDone as Boolean = true;  // chosen on the watch: start right away, pushed: offer start
    var mReadyIntent as System.Intent? = null;  // READY_TO_START: what start launches
    var mOutbox as Array = [] as Array;  // [message, isPortRequest] to the phone, sent one after another
    var mSending as Boolean = false;  // a message of mOutbox is on its way
    var mSendingPortRequest as Boolean = false;  // ... and it is GET_PORT
    var mSendTimer as TIME.Timer?;  // gives up waiting for the confirmation of a message
    var mExitWaits as Number = 0;  // doExitInto() waited this often for mOutbox

    function initialize() {
        AppBase.initialize();

        mGPXorFIT = Ui.loadResource(Rez.Strings.GPXorFIT) as String;
        System.println("GPXorFit = " + mGPXorFIT);

        bluetoothTimer = new TIME.Timer();
        exitTimer = new TIME.Timer();
    }

    // onStart() is called on application start up
    function onStart(state as Lang.Dictionary?) as Void {
        status = Rez.Strings.PressStart;
    }

    // onStop() is called when your application is exiting
    function onStop(state as Lang.Dictionary?) as Void {
    }

    // The only place mState changes. Stops the timers of the state left
    // and tells the phone when an import begins or the app leaves.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function setState(state as Number) as Void {
        var old = mState;
        if (old == state) {
            return;
        }
        System.println("state " + old + " -> " + state);
        mState = state;
        if (old == STATE_WAITING_FOR_PHONE) {
            bluetoothTimer.stop();
        }
        if (old == STATE_REQUESTING_PORT) {
            stopPortTimers();
        }
        if (old == STATE_CHOOSING_SIMILAR) {
            mSimilarCourses = null;
        }
        if (old == STATE_READY_TO_START) {
            mReadyIntent = null;
        }
        if (state == STATE_DOWNLOADING) {
            sendStatus("importing", trackToStart);
        } else if (state == STATE_READY_TO_START) {
            sendStatus("imported", trackToStart);
        } else if (state == STATE_LEAVING) {
            sendStatus("started", trackToStart);
        }
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function canLoadList() as Boolean {
        return $.canLoadListIn(mState);
    }

    // The import failed: show why and let the phone send again.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function failImport(message as String or ResourceId) as Void {
        status = message;
        setState(STATE_IDLE);
        sendStatus("failed", trackToStart);
        Ui.requestUpdate();
    }

    // The user backed out of whatever was in progress. Callbacks still in
    // flight see the changed state and ignore themselves.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function cancel() as Void {
        if (mState == STATE_LEAVING) {
            return;
        }
        var wasImporting = $.isImportingIn(mState) || mState == STATE_READY_TO_START;
        status = Rez.Strings.PressStart;
        mPendingTrackIndex = null;
        setState(STATE_IDLE);
        if (wasImporting) {
            sendStatus("ready", null);
        }
        Ui.requestUpdate();
    }

    // Return the initial view of your application here
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function getInitialView() as [ Ui.Views ] or [ Ui.Views, Ui.InputDelegates ] {
        // One listener for the whole run: it receives port replies and
        // locations pushed by gexporter. Messages that arrived while the app
        // was closed are delivered right away.
        if (Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
        sendStatus("ready", null);
        return [ new gimporterView(true), new gimporterDelegate() ];
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Dictionary) {
            var type = data["type"] as Object?;
            var now = Time.now().value();
            if ("list".equals(type)) {
                // gexporter asks whenever gimporter starts: not worth a message
                sendContentList(false);
            } else if ("delete".equals(type)) {
                var items = $.deleteRequestItems(data, now);
                if (items != null) {
                    deleteContent(items);
                    sendContentList(true);
                } else {
                    System.println("Ignoring stale or malformed delete request");
                }
            } else if (!$.acceptsPushIn(mState) && (("track").equals(type) || ("location").equals(type))) {
                // importing, or already leaving into a course or navigation
                System.println("Busy (state " + mState + "), ignoring " + type);
            } else if ($.isTrackMessage(data, now)) {
                // Messages queued while the app was closed arrive from
                // getInitialView(), before there is a view to push onto.
                mPushedTrack = data;
                if (mPushTimer == null) {
                    mPushTimer = new TIME.Timer();
                }
                mPushTimer.start(method(:onPushedTrack), 300, false);
            } else if ($.isLocationMessage(data, now)) {
                mStartWhenDone = false;
                navigateToLocation(data);
            } else {
                System.println("Ignoring stale or malformed phone message");
            }
            return;
        }
        onPortReceived(msg);
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function onPushedTrack() as Void {
        var track = mPushedTrack;
        mPushedTrack = null;
        if (track == null) {
            return;
        }
        if (!$.acceptsPushIn(mState)) {
            System.println("Busy (state " + mState + "), ignoring pushed track");
            return;
        }
        mServerPort = track["port"] as Number;
        mStartWhenDone = false;
        var fp = track["hash"];
        downloadTrack(track["url"] as String, track["title"] as String, fp instanceof String ? fp : null);
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function loadFingerprints() as Dictionary {
        // Application.Storage needs API 2.4 (not on an Oregon 7xx)
        if (!(App has :Storage)) {
            return {} as Dictionary;
        }
        var fps = Storage.getValue(FINGERPRINTS);
        return fps instanceof Dictionary ? fps as Dictionary : {} as Dictionary;
    }

    // Remember that this content on the watch came from gexporter's
    // track or location with this fingerprint.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function rememberFingerprint(content as PC.Content, fingerprint as String?) as Void {
        if (fingerprint == null || fingerprint.length() == 0 || !(App has :Storage)) {
            return;
        }
        var fps = loadFingerprints();
        fps[$.contentKey($.kindOf(content), content.getId())] = fingerprint;
        Storage.setValue(FINGERPRINTS, fps as Dictionary<Storage.KeyType, Storage.ValueType>);
    }

    // Tell the phone what the app is doing: "ready" (started), "importing"
    // (a track is downloading), "started" (leaving into a course or
    // navigation) or "failed", so gexporter does not send while busy.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function sendStatus(state as String, title as String?) as Void {
        var msg = { "type" => "status", "state" => state, "title" => title == null ? "" : title }
            as Dictionary<Comm.TransmitKeyType, Comm.TransmitType>;
        transmit(msg);
    }

    // Send a message to the phone once the ones before it are through.
    function transmit(msg as Object) as Void {
        queue(msg, false);
    }

    function queue(msg as Object, isPortRequest as Boolean) as Void {
        mOutbox.add([msg, isPortRequest]);
        if (!mSending) {
            sendNext();
        }
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function sendNext() as Void {
        mSending = false;
        if (mSendTimer != null) {
            mSendTimer.stop();
        }
        if (!(Comm has :transmit)) {
            // e.g. Oregon 7xx (API 2.2): nothing can reach the phone, and a
            // missing symbol cannot be caught. A port request falls back.
            var portRequested = false;
            for (var i = 0; i < mOutbox.size(); i++) {
                portRequested = portRequested || ((mOutbox[i] as Array)[1] as Boolean);
            }
            mOutbox = [] as Array;
            if (portRequested) {
                fallbackToDefaultPort();
            }
            return;
        }
        while (mOutbox.size() > 0) {
            var entry = mOutbox[0] as Array;
            mOutbox = mOutbox.slice(1, null);
            var isPortRequest = entry[1] as Boolean;
            if (isPortRequest && mState != STATE_REQUESTING_PORT) {
                continue;  // backed out while it waited
            }
            // before transmit(): the listener may be called right away
            mSending = true;
            mSendingPortRequest = isPortRequest;
            try {
                if (isPortRequest) {
                    // 1 second to wait for the reply
                    if (mPortResponseTimer == null) {
                        mPortResponseTimer = new TIME.Timer();
                    }
                    mPortResponseTimer.start(method(:onPortResponseTimeout), 1000, false);
                }
                Comm.transmit(entry[0] as Comm.TransmitType, null, new OutboxListener());
                // a confirmation that never comes must not block the outbox
                if (mSendTimer == null) {
                    mSendTimer = new TIME.Timer();
                }
                if (mSending) {
                    mSendTimer.start(method(:onTransmitTimeout), 3000, false);
                }
                return;
            } catch (ex) {
                mSending = false;
                System.println("not sent to the phone: " + ex.getErrorMessage());
                if (isPortRequest) {
                    fallbackToDefaultPort();
                }
            }
        }
    }

    function onTransmitDone(success as Boolean) as Void {
        if (!mSending) {
            return;
        }
        if (!success && mSendingPortRequest) {
            // Fall back to default port with delay to let BLE recover
            fallbackToDefaultPort();
        }
        sendNext();
    }

    function onTransmitTimeout() as Void {
        System.println("no confirmation from the phone, sending the next message");
        sendNext();
    }

    function appContent(kind as String) as PC.Iterator? {
        if (!$.hasContentApi()) {
            return null;
        }
        if (kind.equals("course") && (PC has :getAppCourses)) {
            return PC.getAppCourses();
        }
        if (kind.equals("track") && (PC has :getAppTracks)) {
            return PC.getAppTracks();
        }
        if (kind.equals("route") && (PC has :getAppRoutes)) {
            return PC.getAppRoutes();
        }
        if (kind.equals("waypoint") && (PC has :getAppWaypoints)) {
            return PC.getAppWaypoints();
        }
        return null;
    }

    // Reply to the phone's manage screen with everything gimporter stored.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function sendContentList(showStatus as Boolean) as Void {
        var items = [] as Array;
        var fps = loadFingerprints();
        for (var i = 0; i < CONTENT_KINDS.size(); i++) {
            var it = appContent(CONTENT_KINDS[i]);
            if (it != null) {
                $.appendContent(items, CONTENT_KINDS[i], it, fps);
            }
        }
        // forget fingerprints of content deleted on the watch meanwhile
        var kept = {} as Dictionary;
        for (var i = 0; i < items.size(); i++) {
            var item = items[i] as Array;
            var key = $.contentKey(item[0] as String, item[2] as Number);
            if (fps.hasKey(key)) {
                kept[key] = fps[key];
            }
        }
        if (kept.size() != fps.size() && (App has :Storage)) {
            Storage.setValue(FINGERPRINTS, kept as Dictionary<Storage.KeyType, Storage.ValueType>);
        }
        System.println("Sending " + items.size() + " content items to the phone");
        if (showStatus) {
            status = Rez.Strings.PhoneManaging;
            Ui.requestUpdate();
        }
        var reply = { "type" => "content", "items" => items } as Dictionary<Comm.TransmitKeyType, Comm.TransmitType>;
        transmit(reply);
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function deleteContent(items as Array) as Void {
        for (var i = 0; i < items.size(); i++) {
            var item = items[i] as Array;
            var kind = item[0] as String;
            var it = appContent(kind);
            if (it == null) {
                continue;
            }
            var found = $.findContentById(it, item[1] as Number);
            if (found == null || !(found has :remove)) {
                continue;
            }
            var content = found as PC.Course;
            try {
                content.remove();
                System.println("Deleted " + kind + " " + content.getName());
            } catch (ex) {
                // not owned by gimporter, or already gone
                System.println("Could not delete " + kind + ": " + ex.getErrorMessage());
            }
        }
    }

    // Glance shown in the widget carousel on glance-capable devices.
    (:glance)
    function getGlanceView() as [ Ui.GlanceView ] or [ Ui.GlanceView, Ui.GlanceViewDelegate ] or Null {
        return [ new gimporterGlanceView() ];
    }

    function getStatus() as String or ResourceId {
        return status;
    }

    function getTracks() as Array? {
        return tracks;
    }

    function stopPortTimers() as Void {
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }
        if (mPortFallbackTimer != null) {
            mPortFallbackTimer.stop();
        }
    }

    // Helper to proceed after port is resolved (either received or fallback).
    // Dispatches to the correct load function based on pending state.
    // One-shot per port request: the timeout fallback timer, a late reply and
    // a transmit error can all arrive for the same request; the first one
    // leaves REQUESTING_PORT, the others find the app in another state.
    function proceedAfterPortResolved() as Void {
        if (mState != STATE_REQUESTING_PORT) {
            return;
        }
        if (mPendingTrackIndex != null) {
            var index = mPendingTrackIndex;
            mPendingTrackIndex = null;
            loadTrackNumWithPort(index);
        } else {
            loadTrackListWithPort();
        }
    }

    // Delayed fallback callback used after BLE disruption from Comm.transmit().
    // Gives the BLE channel time to recover before making the HTTP request.
    function onPortFallbackDelayed() as Void {
        proceedAfterPortResolved();
    }

    // Fall back to default port with a short delay.
    // The delay allows the BLE channel to recover after a failed Comm.transmit(),
    // which can disrupt the BLE proxy on older devices/firmware.
    function fallbackToDefaultPort() as Void {
        if (mState != STATE_REQUESTING_PORT) {
            return;
        }
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }
        mServerPort = DEFAULT_PORT;
        if (mPortFallbackTimer == null) {
            mPortFallbackTimer = new TIME.Timer();
        }
        mPortFallbackTimer.start(method(:onPortFallbackDelayed), 500, false);
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function requestPortFromAndroid() as Void {
        setState(STATE_REQUESTING_PORT);

        // Check if phone is connected first
        var settings = System.getDeviceSettings();
        if (!settings.phoneConnected) {
            System.println("Phone not connected, using default port");
            mServerPort = DEFAULT_PORT;
            proceedAfterPortResolved();
            return;
        }

        try {
            status = "Requesting port...";
            Ui.requestUpdate();

            // Check if phone app messaging is available; the reply arrives
            // through onPhoneMessage(), registered in getInitialView().
            if (Comm has :registerForPhoneAppMessages) {
                // Send request to Android app; sendNext() starts the
                // response timeout once it is actually on its way
                queue(["GET_PORT"], true);
            } else {
                // Device doesn't support phone app messaging, use default port
                System.println("Device doesn't support phone app messaging, using default port");
                mServerPort = DEFAULT_PORT;
                proceedAfterPortResolved();
            }
        } catch (ex) {
            System.println("Error requesting port: " + ex.getErrorMessage());
            // Stop timeout timer
            if (mPortResponseTimer != null) {
                mPortResponseTimer.stop();
            }
            // Fall back to default port with delay to let BLE recover
            fallbackToDefaultPort();
        }
    }

    function onPortReceived(msg as Comm.PhoneAppMessage) as Void {
        if (mState != STATE_REQUESTING_PORT) {
            // Stray message (duplicate reply, queued leftover from an
            // earlier request) - the listener also fires for those.
            System.println("Ignoring phone message: no port request pending");
            return;
        }

        // Stop the timeout timer since we got a response
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }

        var port = msg.data;
        if (port instanceof Number && port > 0 && port <= 65535) {
            // Received port number
            mServerPort = port;
            System.println("Received port from Android app: " + mServerPort);
            proceedAfterPortResolved();
        } else {
            // Unexpected response type, fall back to default port
            System.println("Unexpected port response type, using default port");
            mServerPort = DEFAULT_PORT;
            proceedAfterPortResolved();
        }
    }

    function onPortResponseTimeout() as Void {
        System.println("Port response timeout, using default port");
        // Timeout reached, fall back to default port with delay to let BLE recover
        fallbackToDefaultPort();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function loadTrackList() as Void {
        if (!canLoadList()) {
            return;
        }
        tracks = null;
        trackToStart = null;
        mPendingTrackIndex = null;

        var settings = System.getDeviceSettings();

        if (! settings.phoneConnected) {
            waitForPhone(Rez.Strings.WaitingForBluetooth);
            return;
        }

        var wifiInfo = (settings has :connectionInfo) ? settings.connectionInfo[:wifi] : null;
        if (wifiInfo != null && wifiInfo.state == System.CONNECTION_STATE_CONNECTED) {
            waitForPhone(Rez.Strings.SwitchOffWifi);
            return;
        }

        // Request port from Android app before making HTTP request
        requestPortFromAndroid();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function waitForPhone(message as ResourceId) as Void {
        setState(STATE_WAITING_FOR_PHONE);
        status = message;
        bluetoothTimer.stop();
        bluetoothTimer.start(method(:loadTrackList), 1000, false);
        Ui.requestUpdate();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function loadTrackListWithPort() as Void {
        status = Rez.Strings.GettingTracklist;
        setState(STATE_LOADING_LIST);
        try {
            var url = "http://127.0.0.1:" + mServerPort + "/dir.json";
            System.println("Requesting track list from: " + url);
            Comm.makeWebRequest(
                url,
                {
                    "type" => mGPXorFIT,
                    "short" => "1",
                    "longname" => "1",
                    // we save shared locations as waypoints; without this
                    // gexporter leaves them out (older versions cannot)
                    "locations" => "1" },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onReceiveTracks) );
        } catch( ex ) {
            setState(STATE_IDLE);
            var msg = ex.getErrorMessage();
            status = (msg != null) ? msg : Rez.Strings.ConnectionFailed;
        }

        Ui.requestUpdate();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function onReceiveTracks(responseCode as Number, data as Dictionary or String or PC.Iterator or Null) as Void {
        if (mState != STATE_LOADING_LIST) {
            // backed out, or the phone pushed something meanwhile
            System.println("track list no longer wanted, ignoring it");
            return;
        }
        setState(STATE_IDLE);
        status = "";

        if (responseCode != 200) {
            System.println("Code " + responseCode.toString());
            status = commErrorString(responseCode, Rez.Strings.ConnectionFailed);
            Ui.requestUpdate();
            return;
        }

        if (!(data instanceof Toybox.Lang.Dictionary) || !data.hasKey("tracks")) {
            System.println("data is no Dictionary or has no track key");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        var trackList = data["tracks"];

        if (!(trackList instanceof Toybox.Lang.Array)) {
            System.println("tracks != Array");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        if (trackList.size() == 0) {
            System.println("tracks is empty");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        // Every element must be a Dictionary with String "url" and "title";
        // TrackChooser and loadTrackNumWithPort rely on this shape unchecked.
        for (var i = 0; i < trackList.size(); i++) {
            var track = trackList[i];
            if (!(track instanceof Toybox.Lang.Dictionary)
                || !(track["url"] instanceof Toybox.Lang.String)
                || !(track["title"] instanceof Toybox.Lang.String)) {
                System.println("track " + i + " is malformed");
                status = Rez.Strings.ConnectionFailed;
                tracks = null;
                Ui.requestUpdate();
                return;
            }
        }

        tracks = trackList;

        $.pushTrackChooser();

    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function loadTrackNum(index as Number) as Void {
        System.println("loadTrack: " + index);
        if (mState != STATE_IDLE && mState != STATE_READY_TO_START) {
            // e.g. a pushed track is downloading under the track list
            System.println("Busy (state " + mState + "), ignoring the choice");
            return;
        }

        mStartWhenDone = true;
        var trackList = tracks;
        if (trackList != null && index < trackList.size()) {
            var track = trackList[index] as Dictionary;
            if ($.isLocation(track)) {
                // A shared destination: nothing to download, the watch
                // saves it as a location from its coordinates.
                navigateToLocation(track);
                return;
            }
        }

        // Store the index for later use
        mPendingTrackIndex = index;

        // Request port from Android app before downloading
        requestPortFromAndroid();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function loadTrackNumWithPort(index as Number) as Void {
        var trackList = tracks;
        if (trackList == null || index >= trackList.size()) {
            // The list was reloaded or cleared while the port handshake
            // was in flight; the stored index no longer means anything.
            System.println("track list changed, aborting load");
            setState(STATE_IDLE);
            status = Rez.Strings.NoTracks;
            Ui.requestUpdate();
            return;
        }

        var track = trackList[index] as Dictionary;
        var fp = track["hash"];
        downloadTrack(track["url"] as String, track["title"] as String, fp instanceof String ? fp : null);
    }

    // Download a track from gexporter and start it; from the track list or
    // when the phone pushes one. A relative url is resolved against
    // mServerPort.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function downloadTrack(url as String, title as String, fingerprint as String?) as Void {
        var trackurl = url;
        trackToStart = title;
        mPendingFingerprint = fingerprint;

        if ((trackurl.length() < 7) || (!"http://".equals(trackurl.substring(0, 7)))) {
            trackurl = "http://127.0.0.1:" + mServerPort + "/" + trackurl;
        }

        status = Rez.Strings.Downloading;
        System.println("GPXorFIT: " + mGPXorFIT);

        Ui.pushView(
            new gimporterView(false),
            new gimporterDelegate(),
            Ui.SLIDE_IMMEDIATE );
        Ui.requestUpdate();

        setState(STATE_DOWNLOADING);
        try {
            if (mGPXorFIT.equals("FIT")) {
                System.println("Downloading FIT");
                Comm.makeWebRequest(
                    trackurl,
                    {
                        "type" => "FIT",
                        "longname" => "1" },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_GET,
                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT },
                    method(:onReceiveTrack) );
            } else {
                System.println("Downloading GPX");
                Comm.makeWebRequest(
                    trackurl,
                    {
                        "type" => "GPX",
                        "longname" => "1" },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_GET,
                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_GPX },
                    method(:onReceiveTrack) );
            }
        } catch( ex ) {
            failImport(Rez.Strings.DownloadNotSupported);
        }

        Ui.requestUpdate();
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function navigateToLocation(track as Dictionary) as Void {
        var name = track["title"] as String;
        var lat = (track["lat"] as String).toDouble();
        var lon = (track["lon"] as String).toDouble();
        System.println("Location: " + name + " " + lat + "," + lon);

        // a pushed location supersedes loading the track list
        setState(STATE_IDLE);
        if (lat == null || lon == null || !(PC has :saveWaypoint)) {
            status = Rez.Strings.DownloadNotSupported;
            Ui.requestUpdate();
            return;
        }

        // Drop an earlier copy, so the lookup below cannot pick a stale one.
        removeAppWaypoints(name);
        PC.saveWaypoint(
            new Position.Location({ :latitude => lat as Double, :longitude => lon as Double, :format => :degrees }),
            { :name => name });

        // saveWaypoint() returns nothing; find the stored waypoint by name.
        var waypoint = null;
        if (PC has :getAppWaypoints) {
            waypoint = $.findWaypoint(PC.getAppWaypoints(), name);
        }
        if (waypoint == null && (PC has :getWaypoints)) {
            waypoint = $.findWaypoint(PC.getWaypoints(), name);
        }
        if (waypoint == null) {
            System.println("saved waypoint not found");
            status = Rez.Strings.ImportFailed;
            Ui.requestUpdate();
            return;
        }

        var fp = track["hash"];
        rememberFingerprint(waypoint, fp instanceof String ? fp : null);
        trackToStart = name;
        status = Rez.Strings.PressStart;
        Ui.requestUpdate();
        // lets the phone mark the location as on the watch
        sendContentList(false);
        // The system asks which activity to navigate with.
        finishImport(waypoint.toIntent());
    }

    function removeAppWaypoints(name as String) as Void {
        if (!(PC has :getAppWaypoints)) {
            return;
        }
        // Collect first: removing while iterating could skip entries.
        var stale = [] as Array<PC.Waypoint>;
        var it = PC.getAppWaypoints();
        var wp = it.next() as PC.Waypoint?;
        while (wp != null) {
            if (wp.getName().equals(name) && (wp has :remove)) {
                stale.add(wp);
            }
            wp = it.next() as PC.Waypoint?;
        }
        for (var i = 0; i < stale.size(); i++) {
            stale[i].remove();
        }
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function doExitInto() as Void {
        var intent = mIntent;
        mIntent = null;
        if (intent == null) {
            return;
        }
        // let "started" and the content list reach the phone first
        if (mSending && mExitWaits < 10) {
            mExitWaits++;
            mIntent = intent;
            exitTimer.start(method(:doExitInto), 200, false);
            return;
        }
        try {
            System.exitTo(intent);
        } catch (ex) {
            // e.g. a second exitTo() while the first is still in progress
            System.println("exitTo failed: " + ex.getErrorMessage());
            if (Comm has :registerForPhoneAppMessages) {
                Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
            }
            failImport(Rez.Strings.ImportFailed);
        }
    }

    // A view of the app became visible. After exitTo() that means the user
    // backed out of the system's activity or navigation prompt: the app is
    // still running. Go back to the start view, ready for the next track,
    // instead of leaving the user on "Download complete" and the phone on
    // "started".
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function onViewShown(isStartView as Boolean) as Void {
        if (mState == STATE_LEAVING && mIntent == null) {
            System.println("Back from exitTo()");
            if (Comm has :registerForPhoneAppMessages) {
                Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
            }
            status = Rez.Strings.PressStart;
            setState(STATE_IDLE);
            sendStatus("ready", null);
            mBackToStart = true;
        }
        if (!mBackToStart) {
            return;
        }
        if (isStartView) {
            mBackToStart = false;
            Ui.requestUpdate();
        } else {
            // not from within onShow(): the view stack is being updated
            exitTimer.start(method(:popStatusView), 50, false);
        }
    }

    function onViewVisible(isStartView as Boolean) as Void {
        mStartViewOnTop = isStartView;
        onViewShown(isStartView);
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function popStatusView() as Void {
        // never the start view: popping it would close the app
        if (!mStartViewOnTop) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
    }

    // The track or location is on the watch. Chosen on the watch: start it.
    // Pushed by the phone: offer it on the start view, so more can follow
    // and the user starts the one they want.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function finishImport(intent as System.Intent) as Void {
        if (mStartWhenDone) {
            exitInto(intent);
            return;
        }
        setState(STATE_READY_TO_START);
        mReadyIntent = intent;
        var title = trackToStart;
        // the view adds "Press Start" below the title
        status = title == null ? "" : normalizeName(title);
        if (!mStartViewOnTop) {
            mBackToStart = true;
            exitTimer.start(method(:popStatusView), 50, false);
        }
        Ui.requestUpdate();
    }

    // Start pressed. @return false if nothing is waiting to be started
    function startReady() as Boolean {
        var intent = mReadyIntent;
        if (mState != STATE_READY_TO_START || intent == null) {
            return false;
        }
        exitInto(intent);
        return true;
    }

    // Leave the app into a course or navigation. Only once: tracks pushed
    // quickly one after another used to call exitTo() a second time while
    // the first was in progress, which crashed with an unhandled exception.
    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function exitInto(intent as System.Intent) as Void {
        if (intent == null || mState == STATE_LEAVING) {
            return;
        }
        mIntent = intent;
        mExitWaits = 0;
        setState(STATE_LEAVING);
        // Messages arriving from now on wait in the mailbox for the next
        // start instead of reaching an app that is about to leave.
        if (Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(null);
        }
        exitTimer.start(method(:doExitInto), 200, false);
    }

    function getSimilarCourses() as Array? {
        return mSimilarCourses;
    }

    function launchSimilarCourse(index as Number) as Void {
        var courses = mSimilarCourses;
        if (mState == STATE_CHOOSING_SIMILAR && courses != null && index < courses.size()) {
            // Courses, Tracks and Routes all provide getName()/toIntent();
            // the cast is only to satisfy the type checker.
            var course = courses[index] as PC.Course;
            System.println("Launching similar course: " + course.getName());
            rememberFingerprint(course, mPendingFingerprint);
            exitInto(course.toIntent());
        }
    }

    // disableGlanceCheck: references foreground-only symbols; never called in
    // the glance scope (the class itself is (:glance), see class comment)
    (:typecheck(disableGlanceCheck))
    function onReceiveTrack(responseCode as Number, downloads as PC.Iterator?) as Void {
        System.println("onReceiveTrack");

        if (mState != STATE_DOWNLOADING) {
            // The user backed out while the download was in flight; the
            // view this callback wants to manipulate is no longer on top.
            System.println("download cancelled, ignoring result");
            return;
        }

        if (responseCode != 200) {
            System.println("Code: " + responseCode);
            failImport(commErrorString(responseCode, Rez.Strings.DownloadFailed));
            return;
        }
        else if (downloads == null) {
            System.println("downloads == null");
            failImport(Rez.Strings.DownloadFailed);
            return;
        }
        else {
            var download = downloads.next();
            System.println("onReceiveTrack: " + (download == null ? null : download.getName() + "/" + download.getId()));

            // FIXME: Garmin
            // Without switchToView() the widget is gone
            Ui.switchToView(new gimporterView(false), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);

            status = Rez.Strings.DownloadComplete;

            if (download != null) {
                Ui.requestUpdate();
                rememberFingerprint(download, mPendingFingerprint);
                // lets the phone mark the track as on the watch
                sendContentList(false);
                finishImport(download.toIntent());
                return;
            }

            status = Rez.Strings.AlreadyDownloaded;

            if (trackToStart == null) {
                System.println("no track name to search for");
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                failImport(Rez.Strings.ImportFailed);
                return;
            }

            var ret = false;
            mSimilarCourses = null;

            if (PC has :getAppCourses) {
                System.println("Searching in App courses");
                ret = searchCourse(PC.getAppCourses());
            }
            if ((ret == false) && (PC has :getCourses)) {
                System.println("Searching in courses");
                ret = searchCourse(PC.getCourses());
            }

            if ((ret == false) && (PC has :getAppTracks)) {
                System.println("Searching in App tracks");
                ret = searchCourse(PC.getAppTracks());
            }
            if ((ret == false) && (PC has :getTracks)) {
                System.println("Searching in tracks");
                ret = searchCourse(PC.getTracks());
            }

            if ((ret == false ) && (PC has :getAppRoutes)) {
                System.println("Searching in App routes");
                ret = searchCourse(PC.getAppRoutes());
            }
            if ((ret == false ) && (PC has :getRoutes)) {
                System.println("Searching in routes");
                ret = searchCourse(PC.getRoutes());
            }

            // Check if we found similar courses to present to user
            if (mState == STATE_LEAVING || mState == STATE_READY_TO_START) {
                // searchCourse() found it
            } else if (mSimilarCourses != null && mSimilarCourses.size() > 0) {
                System.println("Presenting " + mSimilarCourses.size() + " similar courses to user");
                setState(STATE_CHOOSING_SIMILAR);
                $.pushSimilarCourseChooser();
            } else {
                // No similar courses found - import failed
                System.println("No similar courses found, import failed");
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                failImport(Rez.Strings.ImportFailed);
                return;
            }

            Ui.requestUpdate();
            return;
        }
    }

    function normalizeName(name as String) as String {
        var normalized = name;
        var len = normalized.length();
        
        // Remove common course suffixes
        if ((len > 11) && "_course.fit".equals(normalized.substring(len-11, len))) {
            normalized = normalized.substring(0, len-11) as String;
        } else if ((len > 4) && (".fit".equals(normalized.substring(len-4, len)) || ".gpx".equals(normalized.substring(len-4, len)))) {
            normalized = normalized.substring(0, len-4) as String;
        }

        return normalized;
    }

    function searchCourse(cit as PC.Iterator) as Boolean {
        var course;
        var startcourse = null;
        var partialMatches = [] as Array;
        var sclen = 0;
        var trackName = trackToStart;
        if (trackName == null) {
            return false;
        }
        var normalizedTrackName = normalizeName(trackName);
        var tlen = normalizedTrackName.length();

        System.println("Searching for track: '" + trackName + "' (normalized: '" + normalizedTrackName + "')");

        // Search for the longest coursename matching ours
        while (cit != null) {
            course = cit.next();
            if (course == null) {
                break;
            }
            var coursename = (course as PC.Course).getName();
            var normalizedCourseName = normalizeName(coursename);
            var clen = normalizedCourseName.length();

            System.println("Comparing with course: '" + coursename + "' (normalized: '" + normalizedCourseName + "')");

            // Check for exact or prefix matches first
            var isExactMatch = false;
            var isPartialMatch = false;
            
            if (normalizedCourseName.equals(normalizedTrackName)) {
                isExactMatch = true;
                System.println("  Exact match found!");
            } else if (clen <= tlen && normalizedCourseName.equals(normalizedTrackName.substring(0, clen))) {
                isExactMatch = true;
                System.println("  Prefix match found!");
            } else if (clen > tlen && normalizedTrackName.equals(normalizedCourseName.substring(0, tlen))) {
                // Track name is a prefix of course name
                isPartialMatch = true;
                System.println("  Partial match found (track is prefix of course)!");
            }

            if (isExactMatch) {
                // Skip if we already found a longer exact match
                if (sclen > clen) {
                    System.println("  Skipped: already found longer exact match");
                    continue;
                }
                startcourse = course;
                sclen = clen;
                System.println("  Selected as best exact match so far");
            } else if (isPartialMatch) {
                // Collect all partial matches
                partialMatches.add(course as Object);
                System.println("  Added to partial matches list");
            } else {
                System.println("  No match");
            }
        }

        if (startcourse != null) {
            System.println("Found exact course: " + startcourse.getName() + " asking for start");
            mSimilarCourses = null;
            // already imported before: still the content of this track
            rememberFingerprint(startcourse, mPendingFingerprint);
            finishImport(startcourse.toIntent());
            return true;
        } else if (partialMatches.size() > 0) {
            System.println("Found " + partialMatches.size() + " similar courses");
            mSimilarCourses = partialMatches;
            return true;
        } else {
            System.println("No matching course found for: " + trackName);
        }
        return false;
    }
}



// Fonts for the status text, largest first: a long track title steps down
// until it fits.
const STATUS_FONTS = [GFX.FONT_MEDIUM, GFX.FONT_SMALL, GFX.FONT_TINY, GFX.FONT_XTINY] as Array<GFX.FontDefinition>;

// The status text wrapped to the area, or null if it does not fit.
function wrapStatus(dc as GFX.Dc, text as String, font as GFX.FontDefinition, width as Number, height as Number) as String? {
    if (GFX has :fitTextToArea) {
        return GFX.fitTextToArea(text, font, width, height, false);
    }
    // before API 3.1: wrap at spaces ourselves
    var lines = [] as Array<String>;
    var line = "";
    var rest = text;
    while (rest.length() > 0) {
        var sp = rest.find(" ");
        var word = sp == null ? rest : rest.substring(0, sp) as String;
        rest = sp == null ? "" : rest.substring(sp + 1, rest.length()) as String;
        var candidate = line.length() == 0 ? word : line + " " + word;
        if (dc.getTextWidthInPixels(candidate, font) <= width) {
            line = candidate;
        } else if (line.length() == 0 || dc.getTextWidthInPixels(word, font) > width) {
            return null;  // a single word too wide for this font
        } else {
            lines.add(line);
            line = word;
        }
    }
    lines.add(line);
    if (lines.size() * dc.getFontHeight(font) > height) {
        return null;
    }
    var out = lines[0];
    for (var i = 1; i < lines.size(); i++) {
        out += "\n" + lines[i];
    }
    return out;
}

// Drawn in code rather than from a layout per screen size, so it adapts to
// every display: round screens keep the text off the bezel, and long track
// titles wrap or get a smaller font.
class gimporterView extends Ui.View {
    var app as gimporterApp;
    var mAppName as String;
    var mVersion as String;
    var mPressStart as String;
    // the app's first view, rather than one pushed to show a download
    var mIsStartView as Boolean;

    function initialize(isStartView as Boolean) {
        View.initialize();
        app = $.getApp();
        mIsStartView = isStartView;
        mAppName = Ui.loadResource(Rez.Strings.AppName) as String;
        mVersion = Ui.loadResource(Rez.Strings.AppVersion) as String;
        mPressStart = Ui.loadResource(Rez.Strings.PressStart) as String;
    }

    function onShow() as Void {
        app.onViewVisible(mIsStartView);
    }

    function onUpdate(dc as GFX.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(GFX.COLOR_WHITE, GFX.COLOR_BLACK);
        dc.clear();

        var round = System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_RECTANGLE;
        var center = GFX.TEXT_JUSTIFY_CENTER | GFX.TEXT_JUSTIFY_VCENTER;
        // round screens are narrow near the top and bottom
        var edge = round ? 0.14 : 0.08;
        var bottom = (h * (1 - edge)).toNumber();
        var top = (h * edge).toNumber();
        // The Instinct's round subscreen covers the top right corner: it
        // shows the version, the text starts below it.
        var subscreen = (Ui has :getSubscreen) ? Ui.getSubscreen() : null;
        if (subscreen != null) {
            var sx = subscreen.x as Number;
            var sy = subscreen.y as Number;
            var sw = subscreen.width as Number;
            var sh = subscreen.height as Number;
            dc.drawText(sx + sw / 2, sy + sh / 2, GFX.FONT_XTINY, mVersion, center);
            top = sy + sh;
            bottom = h;
        } else {
            dc.drawText(w / 2, top, GFX.FONT_XTINY, mAppName, center);
            dc.drawText(w / 2, bottom, GFX.FONT_XTINY, mVersion, center);
        }

        var status = app.getStatus();
        var text = status instanceof String ? status as String : Ui.loadResource(status as ResourceId) as String;
        if (text.equals("")) {
            text = mPressStart;
        }
        // the widest band of a round screen is the middle
        var areaW = (w * (round ? 0.78 : 0.92)).toNumber();
        var lineH = dc.getFontHeight(GFX.FONT_XTINY);
        var areaTop = subscreen != null ? top : top + lineH / 2;
        var areaBottom = subscreen != null ? bottom - lineH / 4 : bottom - lineH / 2;
        // A track waiting to be started: its title, and how to start it
        // in a smaller font below.
        if (app.mState == STATE_READY_TO_START) {
            var hintH = dc.getFontHeight(GFX.FONT_TINY);
            dc.drawText(w / 2, areaBottom - hintH / 2, GFX.FONT_TINY, mPressStart, center);
            areaBottom -= hintH;
        }
        var areaH = areaBottom - areaTop;
        var areaMid = areaTop + areaH / 2;
        var font = STATUS_FONTS[STATUS_FONTS.size() - 1];
        var fitted = null;
        for (var i = 0; i < STATUS_FONTS.size() && fitted == null; i++) {
            font = STATUS_FONTS[i];
            fitted = $.wrapStatus(dc, text, font, areaW, areaH);
        }
        if (fitted == null) {
            fitted = (GFX has :fitTextToArea) ? GFX.fitTextToArea(text, font, areaW, areaH, true) : text;
        }
        dc.drawText(w / 2, areaMid, font, fitted, center);
    }
}

class gimporterDelegate extends Ui.BehaviorDelegate {
    var app as gimporterApp;

    function initialize() {
        BehaviorDelegate.initialize();
        app = $.getApp();
    }

    function onBack() as Boolean {
        // Cancel whatever is in flight - callbacks check the state and
        // bail out instead of manipulating a view stack we just changed.
        app.cancel();
        return false;
    }

    function onMenu() as Boolean {
        app.loadTrackList();
        return true;
    }

    function onSelect() as Boolean {
        if (!app.startReady()) {
            app.loadTrackList();
        }
        return true;
    }
}

class SimilarCourseChooser extends Ui.Menu {

    function initialize() {
        var app = $.getApp();
        Menu.initialize();
        Menu.setTitle(Rez.Strings.SimilarCourseChooserTitle);
        var courses = app.getSimilarCourses();
        
        if (courses != null) {
            for(var i = 0; i < courses.size() && i < ITEM_SYMBOLS.size(); i++) {
                var course = courses[i] as PC.Course;
                Menu.addItem(
                    course.getName(),
                    $.itemToSym(i) );
            }
        }
    }
}

class SimilarCourseChooserDelegate extends Ui.MenuInputDelegate {
    var app as gimporterApp;

    function initialize() {
        MenuInputDelegate.initialize();
        app = $.getApp();
    }

    function onMenuItem(item as Symbol) as Void {
        app.launchSimilarCourse($.symToItem(item));
    }
}
