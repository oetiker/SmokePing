/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * A label with the ability to link out. Based on Label.
 */
qx.Class.define('tr.ui.Link', {
    extend : qx.ui.basic.Label,




    /*
            *****************************************************************************
               CONSTRUCTOR
            *****************************************************************************
            */

    /**
             * @param text {String} Initial label
             * @param url  {String} Where to link to
             * @param color {String} Hex Color for the text
             * @param font {String} Font from string representation
             */
    construct : function(text, url, color, font) {
        this.base(arguments, text);

        if (color) {
            this.setTextColor(color);
        }

        if (font) {
            this.setFont(qx.bom.Font.fromString(font));
        }

        this.set({
            cursor  : 'pointer',
            opacity : 0.9
        });

        this.addListener('click', function(e) {
            window.open(url, '__new');
        });

        this.addListener('mouseover', function(e) {
            this.setOpacity(1);
        }, this);

        this.addListener('mouseout', function(e) {
            this.setOpacity(0.7);
        }, this);
    }
});