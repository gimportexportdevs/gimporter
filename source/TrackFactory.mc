using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;

class TrackFactory extends Ui.PickerFactory {
    var mTracks;
    var mFont;

    function initialize(tracks, options) {
        PickerFactory.initialize();

        mTracks = tracks;

        if(options != null) {
            mFont = options.get(:font);
        }

        if(mFont == null) {
            mFont = Gfx.FONT_SMALL;
        }
    }

    function getIndex(value) {
        if(value instanceof String) {
                for(var i = 0; i < mTracks.size(); ++i) {
                    if(value.equals(mTracks[trackindex]["url"])) {
                        return i;
                    }
                }
        } else {
            for(var i = 0; i < mTracks.size(); ++i) {
                if(mTracks[i].equals(value)) {
                    return i;
                }
            }
        }
        return 0;
    }

    function getSize() {
        return mTracks.size();
    }

    function getValue(index) {
        return mTracks[index];
    }

    function getDrawable(index, selected) {
        return new Ui.Text({:text=>mTracks[index]["title"], :color=>Gfx.COLOR_WHITE,
                           :font=>mFont, :locX=>Ui.LAYOUT_HALIGN_CENTER, :locY=>Ui.LAYOUT_VALIGN_CENTER});
    }
}
