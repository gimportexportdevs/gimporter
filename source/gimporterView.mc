using Toybox.WatchUi as Ui;
using Toybox.Communications as comm;

class gimporterView extends Ui.View {
        var tracks = null;
        var trackindex = 0;
	var showlist = false;
	var status = "";
	var version;
	var t1;
	var t2;
	var t3;
	var st;
        function initialize() {
                View.initialize();
                tracks = null;
        }

        // Load your resources here
        function onLayout(dc) {
                setLayout(Rez.Layouts.MainLayout(dc));
                System.println("onLayout");
                t1 = findDrawableById("t1");
                t2 = findDrawableById("t2");
                t3 = findDrawableById("t3");
		st = findDrawableById("status");
		version = Ui.loadResource( Rez.Strings.AppVersion );
        }

        function onReceive(responseCode, data) {
		status = "";

                if (responseCode == comm.BLE_CONNECTION_UNAVAILABLE) {
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

        // Called when this View is brought to the foreground. Restore
        // the state of this View and prepare it to be shown. This includes
        // loading resources into memory.
        function onShow() {
		getTracks();
	}

        function getTracks() {
                //System.println("onShow");
		status = "Getting Tracklist";
		showlist = false;
		Ui.requestUpdate();

                comm.makeWebRequest("http://localhost:22222/dir.json", null, 
                                    {
                                            :method => comm.HTTP_REQUEST_METHOD_GET,
                                                    :headers => {
                                                    "Content-Type" => comm.REQUEST_CONTENT_TYPE_JSON
                                            },
                                                    :responseType => comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                                                             }, method(:onReceive) );
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

        // Update the view
        function onUpdate(dc) {
                if ((tracks instanceof Toybox.Lang.Array) && (tracks.size() > 0)) {
			if (showlist) {
				t1.setText("⏶⏶⏶");
				t3.setText("⏷⏷⏷");
			} else {
				t1.setText("");
				t3.setText("");
			}
			t2.setText(tracks[trackindex]["title"]);
		} else {
			if (showlist) {
				status = "no tracks!!!";
			}
		}
		if (status.equals("")) {
			st.setText(version);
		} else {
			st.setText(status);
		}

                // Call the parent onUpdate function to redraw the layout
                View.onUpdate(dc);
        }

        // Called when this View is removed from the screen. Save the
        // state of this View here. This includes freeing resources from
        // memory.
        function onHide() {
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
                comm.makeWebRequest(trackurl, null,
                                    {
                                            :method => comm.HTTP_REQUEST_METHOD_GET,
                                                    :responseType => comm.HTTP_RESPONSE_CONTENT_TYPE_FIT
                                                    }, method(:onReceiveTrack) );
        }
        function onReceiveTrack(responseCode, data) {
                System.println("onReceiveTrack");
                if (responseCode == comm.BLE_CONNECTION_UNAVAILABLE) {
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
