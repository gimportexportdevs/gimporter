using Toybox.WatchUi as Ui;
using Toybox.Communications as comm;

class importerView extends Ui.View {
	var tracks = null;

    function initialize() {
        View.initialize();
    }

    // Load your resources here
    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
        System.println("onLayout");
  		findDrawableById("t1").setText("T1");
   		findDrawableById("t2").setText("T2");
    	findDrawableById("t3").setText("T3");
    	findDrawableById("t4").setText("T4");
    }

	function onReceive(responseCode, data) {
	    if (responseCode == 104) {
        	System.println("Bluetooth disconnected");
	    	findDrawableById("t1").setText("Bluetooth disconnected");
			Ui.requestUpdate();
	    	return;
	    }

        System.println("onReceive : ");
        System.println(data);
	    if (data == null) {
        	System.println("data == null" + responseCode.toString());
	    	findDrawableById("t1").setText("null " + responseCode.toString());
			Ui.requestUpdate();
	    	return;
	    }
		var tracks = data["tracks"];

	    if (tracks == null) {
        	System.println("tracks == null");
	    	findDrawableById("t2").setText("null");
			Ui.requestUpdate();
	    	return;
	    }
	   
        System.println(tracks);
        if (tracks instanceof Toybox.Lang.Array) {
        	System.println("tracks == Array");
        } else {
        	System.println("tracks != Array");
	    	findDrawableById("t2").setText("no Array");
			Ui.requestUpdate();
			return;
		}

		for (var i = 0; i < tracks.size(); i++) {
			System.println(tracks[i]["title"] + " - " + tracks[i]["url"]);
		}
		
    	if (tracks.size() > 0) {
	    	findDrawableById("t1").setText(tracks[0]["title"]);
	    }
    	if (tracks.size() > 1) {
	    	findDrawableById("t2").setText(tracks[1]["title"]);
	    }
    	if (tracks.size() > 2) {
	    	findDrawableById("t3").setText(tracks[2]["title"]);
	    }
    	if (tracks.size() > 3) {
	    	findDrawableById("t4").setText(tracks[3]["title"]);
	    }
		Ui.requestUpdate();
	}

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
        System.println("onShow");
        comm.makeWebRequest("http://127.0.0.1:22222/dir.json", null, 
        { :method => comm.HTTP_REQUEST_METHOD_GET,
          :headers => {
				"Content-Type" => comm.REQUEST_CONTENT_TYPE_URL_ENCODED,
      			"Accept" => "application/json"
   			},
          :responseType => comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onReceive) );
    }

    // Update the view
    function onUpdate(dc) {
		System.println("onUpdate");

        // Call the parent onUpdate function to redraw the layout
        View.onUpdate(dc);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }

}
