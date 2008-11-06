/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * a widget showing the footer
 */
qx.Class.define('tr.ui.Footer', {
    extend : qx.ui.container.Composite,




    /*
                *****************************************************************************
                   CONSTRUCTOR
                *****************************************************************************
                */

    construct : function(text, url) {
        this.base(arguments, new qx.ui.layout.HBox().set({ alignX : 'right' }));
        this.add(new tr.ui.Link(text, url, '#888', '10px sans-serif'));
    }
});