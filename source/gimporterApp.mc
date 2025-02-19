import Toybox.Lang;

using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;
using Toybox.Timer as TIME;
using Toybox.System as System;
using Toybox.Graphics as GFX;

function getApp() as gimporterApp {
    return App.getApp() as gimporterApp;
}

class gimporterApp extends App.AppBase {
    var tracks as Array? = null;
    var trackToStart as String?;
    var canLoadList as Boolean;
    var status as String or ResourceId = "";
    var mGPXorFIT as String;
    var bluetoothTimer as TIME.Timer;
    var exitTimer as TIME.Timer;
    var mIntent as System.Intent? = null;

    function initialize() {
        AppBase.initialize();

        mGPXorFIT = Ui.loadResource(Rez.Strings.GPXorFIT);
        System.println("GPXorFit = " + mGPXorFIT);
        
        canLoadList = true;
        bluetoothTimer = new TIME.Timer();
        exitTimer = new TIME.Timer();
    }

    // onStart() is called on application start up
    function onStart(state as Lang.Dictionary?) as Void {
        //loadTrackList();
        status = Rez.Strings.PressStart;
    }

    // onStop() is called when your application is exiting
    function onStop(state as Lang.Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [ Ui.Views ] or [ Ui.Views, Ui.InputDelegates ] {
        return [ new gimporterView(), new gimporterDelegate() ];
    }

    function getStatus() as String {
        return status;
    }

    function getTracks() as Array {
        return tracks;
    }

    function loadTrackList() as Void {
        tracks = null;
        trackToStart = null;
        mIntent = null;

        var settings = System.getDeviceSettings();

        if (! settings.phoneConnected) {
            bluetoothTimer.stop();
            status = Rez.Strings.WaitingForBluetooth;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        if ((settings has :connectionInfo) && (settings.connectionInfo has :wifi) && (settings.connectionInfo[:wifi].state == System.CONNECTION_STATE_CONNECTED)) {
            bluetoothTimer.stop();
            status = Rez.Strings.SwitchOffWifi;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        // if ((settings has :connectionInfo) || !(settings.connectionInfo has :bluetooth) || (settings.connectionInfo[:bluetooth].state != CONNECTION_STATE_CONNECTED)) {
        //     bluetoothTimer.stop();
        //     status = Rez.Strings.WaitingForBluetooth;
        //     bluetoothTimer.start(method(:loadTrackList), 1000, false);
        //     Ui.requestUpdate();
        //     return;
        // }

        status = Rez.Strings.GettingTracklist;
        canLoadList = false;
        try {
            Comm.makeWebRequest(
                "http://127.0.0.1:22222/dir.json",
                {
                    "type" => mGPXorFIT,
                    "short" => "1",
                    "longname" => "1" },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                    :headers => {
                        "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON },
                    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onReceiveTracks) );
        } catch( ex ) {
            canLoadList = true;
            status = ex.getErrorMessage();
        }

        Ui.requestUpdate();

    }

    function onReceiveTracks(responseCode as Number, data as Dictionary) as Void {
        status = "";
        canLoadList = true;

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }

        if (responseCode != 200) {
            System.println("data == null\nCode " + responseCode.toString() + "\n");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        if (!(data instanceof Toybox.Lang.Dictionary)) {
            System.println("data is not Dict");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        if (! data.hasKey("tracks")) {
            System.println("data has no track key");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        tracks = data["tracks"];

        if (tracks == null) {
            System.println("tracks == null");
            status = Rez.Strings.NoTracks;
            Ui.requestUpdate();
            return;
        }

        if (!(tracks instanceof Toybox.Lang.Array)) {
            System.println("tracks != Array");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        Ui.pushView(new TrackChooser(0), new TrackChooserDelegate(0), Ui.SLIDE_IMMEDIATE);

    }

    function loadTrackNum(index as Number) as Void {
        System.println("loadTrack: " + tracks[index].toString());

        // TODO: check hasKey
        var trackurl = tracks[index]["url"];
        trackToStart = tracks[index]["title"];

        if ((trackurl.length() < 7) || (!trackurl.substring(0, 7).equals("http://"))) {
            trackurl = "http://127.0.0.1:22222/" + trackurl;
        }

        status = Rez.Strings.Downloading;
        canLoadList = false;
        System.println("GPXorFIT: " + mGPXorFIT);

        Ui.pushView(new gimporterView(), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);
        Ui.requestUpdate();

        try {
            if (mGPXorFIT.equals("FIT")) {
                System.println("Downloading FIT");
                Comm.makeWebRequest(trackurl, { "type" => "FIT", "longname" => "1" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT}, method(:onReceiveTrack) );
            } else {
                System.println("Downloading GPX");
                Comm.makeWebRequest(trackurl, { "type" => "GPX", "longname" => "1" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_GPX}, method(:onReceiveTrack) );
            }
        } catch( ex ) {
            status = Rez.Strings.DownloadNotSupported;
        }
    }

    function doExitInto() as Void {
        if (mIntent != null) {
            System.exitTo(mIntent);
            mIntent = null;
        }
    }

    function exitInto(intent as System.Intent) as Void {
        if (intent != null) {
            mIntent = intent;
            exitTimer.start(method(:doExitInto), 200, false);
        }
    }

    function onReceiveTrack(responseCode as Number, downloads as PC.Iterator) as Void {
        System.println("onReceiveTrack");

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }
        else if (responseCode != 200) {
            System.println("Code: " + responseCode);
            status = Rez.Strings.DownloadFailed;
            Ui.requestUpdate();
            return;
        }
        else if (downloads == null) {
            System.println("downloads == null");
            status = Rez.Strings.DownloadFailed;
            Ui.requestUpdate();
            return;
        }
        else {
            var download = downloads.next();
            System.println("onReceiveTrack: " + (download == null ? null : download.getName() + "/" + download.getId()));

            // FIXME: Garmin
            // Without switchToView() the widget is gone
            Ui.switchToView(new gimporterView(), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);

            status = Rez.Strings.DownloadComplete;

            if (download != null) {
                Ui.requestUpdate();
                exitInto(download.toIntent());
                return;
            }

            status = Rez.Strings.AlreadyDownloaded;

            // if (trackToStart.length() > 4) {
            //     var postfix = trackToStart.substring(trackToStart.length()-4, trackToStart.length()).toLower();
            //     if (postfix.equals(".fit") || postfix.equals(".gpx")) {
            //         trackToStart = trackToStart.substring(0, trackToStart.length()-4);
            //     }
            // }
            // if (trackToStart.length() > 15) {
            //     trackToStart = trackToStart.substring(0, 15);
            // }

            var ret = false;

            if (PC has :getAppCourses) {
                System.println("Searching in App courses");
                ret = searchCourse(PC.getAppCourses());
            }
            if (PC has :getCourses) {
                System.println("Searching in courses");
                ret = searchCourse(PC.getCourses());
            }

            if ((ret == false) && (PC has :getAppTracks)) {
                System.println("Searching in App tracks");
                ret = searchCourse(PC.getTracks());
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

            Ui.requestUpdate();
            return;
        }
    }

    function searchCourse(cit as PC.Iterator) as Boolean {
        var course;
        var startcourse = null;
        // var startcoursename = null;  //not-used
        var sclen = 0;
        var tlen = trackToStart.length();

        // Search for the longest coursename matching ours
        while (cit != null) {
            course = cit.next();
            if (course == null) {
                break;
            }
            var coursename = course.getName();
            var clen = coursename.length();

            if ((clen > 11) && coursename.substring(clen-11, clen).equals("_course.fit")) {
                coursename = coursename.substring(0, clen-11);
                clen = clen - 11;
            }

            // Shortened course names end with 60b2 on Fenix 5

            System.println("Checking if " + trackToStart + " == " + coursename);

            if ((clen > tlen) || (sclen > clen) || (!trackToStart.substring(0, clen).equals(coursename))) {
                continue;
            }
            startcourse = course;
            // startcoursename = coursename;
            sclen = clen;
        }

        if (startcourse != null) {
            System.println("Found course: " + startcourse.getName() + " asking for start");
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            canLoadList = true;
            status = Rez.Strings.PressStart;
            // FIXME: Garmin
            // I can't do System.exitTo(course.toIntent())
            // It causes the Fenix5 to be in a strange state
            exitInto(startcourse.toIntent()); // workaround
            return true;
        } else {
            System.println("No course found");
        }
        return false;
    }
}



class gimporterView extends Ui.View {
    var st as Ui.Text?;
    var ps as String or ResourceId = "";
    var app as gimporterApp;

    function initialize() {
        View.initialize();
        app = $.getApp();
    }

    function onLayout(dc as GFX.Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
        st = findDrawableById("status");
        ps = Ui.loadResource(Rez.Strings.PressStart);
    }

    function onUpdate(dc as GFX.Dc) as Void {
        var status = app.getStatus();
        if (status.equals("")) {
            st.setText(ps);
        } else {
            st.setText(status);
        }

        View.onUpdate(dc);
    }
}

class gimporterDelegate extends Ui.BehaviorDelegate {
    var app as gimporterApp;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onBack() as Boolean {
        app.canLoadList = true;
        app.status = Rez.Strings.PressStart;
        Ui.requestUpdate();
        return false;
    }

    function onMenu() as Boolean {
        if (app.canLoadList) {
            app.loadTrackList();
        }
        return true;
    }

    function onSelect() as Boolean {
        if (app.canLoadList) {
            app.loadTrackList();
        }
        return true;
    }
}
