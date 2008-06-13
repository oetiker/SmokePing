/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * a widget showing the footer
 */

qx.Class.define('Tr.ui.Footer', 
{
    extend: qx.ui.layout.HorizontalBoxLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    construct: function (text,url) {
        this.base(arguments);
        this.set({
            horizontalChildrenAlign: 'right',
            height: 'auto'
        });
        var logo = new qx.ui.form.Button(text);
        logo.set({
            textColor: '#b0b0b0',
            backgroundColor: null,
            font: qx.ui.core.Font.fromString('10px sans-serif'),
            border: null
        });
            
        logo.addEventListener('execute', function(e){
            var w = new qx.client.NativeWindow(url);
            w.set({
                width: 1000,
                height: 800
            });
            w.open()
        });
        this.add(logo);
    }
});
 
 
