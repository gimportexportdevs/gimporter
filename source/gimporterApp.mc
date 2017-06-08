using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;
using Toybox.Timer as Timer;
using Toybox.System as System;

class gimporterApp extends App.AppBase {
    var tracks;
    var trackToStart;
    var canLoadList;
    var status;
    var mGPXorFIT;
    var bluetoothTimer;
    var mCourse;
    var exitTimer;

    function initialize() {
        AppBase.initialize();
        tracks = null;
        canLoadList = true;
        status = "";
        mGPXorFIT = getPropertyDef("GPXorFIT", "FIT");
        bluetoothTimer = new Timer.Timer();
        exitTimer = new Timer.Timer();
        mCourse = null;
    }

    function getPropertyDef(key, def) {
        var val = getProperty(key);
        if (val == null) {
            return def;
        } else {
            return val;
        }
    }

    // onStart() is called on application start up
    function onStart(state) {
        //loadTrackList();
        status = Rez.Strings.PressStart;
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        return [ new gimporterView(), new gimporterDelegate() ];
    }

    function getStatus() {
        return status;
    }

    function getTracks() {
        return tracks;
    }

    function loadTrackList() {
        if (! System.getDeviceSettings().phoneConnected) {
            bluetoothTimer.stop();
            status = Rez.Strings.WaitingForBluetooth;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        status = Rez.Strings.GettingTracklist;
        canLoadList = false;
        try {
            Comm.makeWebRequest("http://localhost:22222/dir.json", { "type" => mGPXorFIT, "short" => "1" },
                                {
                                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                                        :headers => {
                                        "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
                                    },
                                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                                             }, method(:onReceiveTracks)
                );
        } catch( ex ) {
            canLoadList = true;
            status = ex.getErrorMessage();
        }

        Ui.requestUpdate();

    }

    function onReceiveTracks(responseCode, data) {
        status = "";
        canLoadList = true;

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }

        if (responseCode != 200) {
            System.println("data == null" + responseCode.toString());
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

    function loadTrackNum(index) {
        System.println("loadTrack: " + tracks[index].toString());

        // TODO: check hasKey
        var trackurl = tracks[index]["url"];
        trackToStart = tracks[index]["title"];

        if ((trackurl.length() < 7) || (!trackurl.substring(0, 7).equals("http://"))) {
            trackurl = "http://localhost:22222/" + trackurl;
        }

        status = Rez.Strings.Downloading;
        canLoadList = false;
        System.println("GPXorFIT: " + mGPXorFIT);

        Ui.pushView(new gimporterView(), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);
        Ui.requestUpdate();

        try {
            if (mGPXorFIT.equals("FIT")) {
                System.println("Downloading FIT");
                Comm.makeWebRequest(trackurl, { "type" => "FIT" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT}, method(:onReceiveTrack) );
            } else {
                System.println("Downloading GPX");
                Comm.makeWebRequest(trackurl, { "type" => "GPX" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_GPX}, method(:onReceiveTrack) );
            }
        } catch( ex ) {
            status = Rez.Strings.DownloadNotSupported;
        }
    }

    function doExitInto() {
        if (mCourse != null) {
            System.exitTo(mCourse.toIntent());
            mCourse = null;
        }
    }

    function exitInto(course) {
        if (course != null) {
            mCourse = course;
            exitTimer.start(method(:doExitInto), 200, false);
        }
    }

    function onReceiveTrack(responseCode, data) {
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
        else if (data == null) {
            System.println("data == null");
            status = Rez.Strings.DownloadFailed;
            Ui.requestUpdate();
            return;
        }
        else {
            System.println(data.toString());

            // FIXME: Garmin
            // Without switchToView() the widget is gone
            // Ui.switchToView(new gimporterView(), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);
            status = Rez.Strings.DownloadComplete;

            if (trackToStart.length() > 4) {
                var postfix = trackToStart.substring(trackToStart.length()-4, trackToStart.length()).toLower();
                if (postfix.equals(".fit") || postfix.equals(".gpx")) {
                    trackToStart = trackToStart.substring(0, trackToStart.length()-4);
                }
            }
            if (trackToStart.length() > 15) {
                trackToStart = trackToStart.substring(0, 15);
            }

            var cit = PC.getCourses();
            var course;
            while (true) {
                course = cit.next();
                if (course == null) {
                    break;
                }
                var coursename = course.getName();
                if (coursename.equals(trackToStart) || coursename.equals(trackToStart + "_course.fit")) {
                    System.println("Found course: " + course.getName() + " asking for start");
                    Ui.popView(Ui.SLIDE_IMMEDIATE);
                    canLoadList = true;
                    status = Rez.Strings.PressStart;
                    // FIXME: Garmin
                    // I can't do System.exitTo(course.toIntent())
                    // It causes the Fenix5 to be in a strange state
                    exitInto(course);
                    break;
                } else {
                    System.println(course.getName() + " != " + trackToStart);
                }
            }
            Ui.requestUpdate();
            return;
        }
    }
}

class gimporterView extends Ui.View {
    var st;
    var ps;
    var app;

    function initialize() {
        View.initialize();
        app = App.getApp();
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
        st = findDrawableById("status");
        ps = Ui.loadResource(Rez.Strings.PressStart);
    }

    function onUpdate(dc) {
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
    var app;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onBack() {
        app.canLoadList = true;
        app.status = Rez.Strings.PressStart;
    }

    function onKey(key) {
        var k = key.getKey();

        if (k == Ui.KEY_ENTER || k == Ui.KEY_START || k == Ui.KEY_RIGHT) {
            if (app.canLoadList) {
                app.loadTrackList();
            }
            return true;
        }

        return BehaviorDelegate.onKey(key);
    }
}
