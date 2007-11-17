/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * The widget showing a detail graph
 */

qx.Class.define('Smokeping.ui.Navigator',
{
    extend: qx.ui.window.Window,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param graph_url   {String}   Url to the explorable graph
     *
     */

    construct: function (image) {
		with(this){
			base(arguments,this.tr("Smokeping Graph Navigator"));
			var plot = new qx.ui.basic.Image(image.getSource());			
			setZIndex(100000);
			add(plot);
		}
		
    }


});
 
 
