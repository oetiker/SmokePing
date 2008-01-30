/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping graph overview
 */

qx.Class.define('Smokeping.ui.GraphList', 
{
    extend: qx.ui.layout.FlowLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param base_url   {String}   Path to the location of the image generator
     *
     */

    construct: function () {

        with(this){
			base(arguments);
			set({
            	overflow: 'auto',
	            backgroundColor: 'white',
		    	border: new qx.ui.core.Border(1,'solid','#a0a0a0'),
 	           	width: '100%',
            	height: '100%',
            	verticalSpacing: 10,
            	horizontalSpacing: 10,
				padding: 10
			})
        };
   		qx.event.message.Bus.subscribe('sp.menu.folder',this._load_graphs,this);
    },

	members: {
		_load_graphs: function(m){
			var files = m.getData()
			this.removeAll();
			for(var i=0;i<files.length;i++){
   			   	var image = new Smokeping.ui.Graph(files[i]);
				this.add(image);
			}
		}
	}
	

});
 
 
