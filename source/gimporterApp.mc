using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;

class gimporterApp extends App.AppBase {
    var tracks;
    var trackindex;
    var showlist;
    var status;

    function initialize() {
        AppBase.initialize();
	tracks = null;
	trackindex = 0;
	showlist = false;
	status = "";
    }

    // onStart() is called on application start up
    function onStart(state) {
	loadTrackList();
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        return [ new gimporterView(), new gimporterDelegate() ];
    }

    function loadTrackList() {
	//System.println("onShow");
	status = "Getting Tracklist";
	showlist = false;
	Ui.requestUpdate();

	Comm.makeWebRequest("http://localhost:22222/dir.json", null,
			    {
				:method => Comm.HTTP_REQUEST_METHOD_GET,
				    :headers => {
				    "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
				},
				    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
					 }, method(:onReceiveTracks) );
    }

    function onReceiveTracks(responseCode, data) {
	status = "";

	if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
	    System.println("Bluetooth disconnected");
	    status = "Bluetooth disconnected";
	    Ui.requestUpdate();
	    return;
	}

	System.println("onReceive : ");
	//System.println(data);
	if (responseCode != 200) {
	    System.println("data == null" + responseCode.toString());
	    status = "Connection failed";
	    Ui.requestUpdate();
	    return;
	}
	tracks = data["tracks"];

	if (tracks == null) {
	    System.println("tracks == null");
	    status = "No tracks";
	    Ui.requestUpdate();
	    return;
	}

	//System.println(tracks);
	if (tracks instanceof Toybox.Lang.Array) {
	    System.println("tracks == Array");
	} else {
	    System.println("tracks != Array");
	    status = "No tracks";
	    tracks = null;
	    Ui.requestUpdate();
	    return;
	}

	showlist = true;
	trackindex = 0;
	Ui.requestUpdate();
    }

    function previousTrack() {
	if (!showlist || (tracks == null)) {
	    return;
	}

	trackindex = (trackindex - 1 + tracks.size()) % tracks.size();
	status = "";
	Ui.requestUpdate();

    }

    function nextTrack() {
	if (!showlist || (tracks == null)) {
	    return;
	}
	trackindex = (trackindex + 1) % tracks.size();
	status = "";
	Ui.requestUpdate();

    }

    function getTrackSize() {
	if (!(tracks instanceof Toybox.Lang.Array)) {
	    return 0;
	}
	return tracks.size();
    }

    function getCurrentTrackTitle() {
	return tracks[trackindex]["title"];
    }

    function showList() {
	return showlist;
    }

    function getStatus() {
	return status;
    }

    function loadTrack() {
	if (!showlist || (tracks == null)) {
	    return;
	}

	System.println("loadTrack");

	var trackurl = tracks[trackindex]["url"];

	status = "Downloading";
	Ui.requestUpdate();
	showlist = false;
	Comm.makeWebRequest(trackurl, null,
			    {
				:method => Comm.HTTP_REQUEST_METHOD_GET,
				    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT
				    }, method(:onReceiveTrack) );
    }

    function onReceiveTrack(responseCode, data) {
	System.println("onReceiveTrack");
	if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
	    System.println("Bluetooth disconnected");
	    status = "Bluetooth disconnected";
	    Ui.requestUpdate();
	    return;
	}

	System.println("Code: " + responseCode);

	if (responseCode == 200) {
	    if (data == null) {
		System.println("data == null");
		status = "Download failed";
	    } else {
		// TODO: What the heck is in data ???

		System.println(data);
		//System.println(data["args"]);
		if (data instanceof Toybox.Lang.Array) {
		    for( var i = 0; i < data.size(); i++ ) {
			System.println("data[" + i.toString() + "] = " + data[i].toString());
		    }
		} else if (data instanceof Toybox.Lang.Dictionary) {
		    keys = data.keys();

		    for( var i = 0; i < keys.size(); i++ ) {
			System.println("data['" + keys[i].toString() + "']");
		    }
		    //} else if (data instanceof Toybox.Lang.String) {
		}
		status = "Download finished";
	    }
	} else {
	    status = "Download failed";
	}
	showlist = true;
	Ui.requestUpdate();
	return;
    }
}
