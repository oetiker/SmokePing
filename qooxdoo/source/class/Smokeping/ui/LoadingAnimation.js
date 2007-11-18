/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * The widget showing a detail graph
 */

qx.Class.define('Smokeping.ui.LoadingAnimation',
{
    extend: qx.ui.layout.CanvasLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param graph_url   {String}   Url to the explorable graph
     *
     */

    construct: function () {
		this.base(arguments);
		this.set({
			width: '100%',
			height: '100%'
		});
		var plane = new qx.ui.basic.Terminator();
		plane.set({
			width: '100%',
			height: '100%',
			backgroundColor: '#f0f0f0',
			opacity: 1
		});
		this.add(plane);

		var centerbox = new qx.ui.layout.BoxLayout();
		centerbox.set({
			width: '100%',
			height: '100%',
            horizontalChildrenAlign: 'center',
	        verticalChildrenAlign: 'middle'
		});
		var animation = new qx.ui.basic.Image(qx.io.Alias.getInstance().resolve('SP/image/ajax-loader.gif'));
		centerbox.add(animation);
		this.add(centerbox);
    }
});
 
 
