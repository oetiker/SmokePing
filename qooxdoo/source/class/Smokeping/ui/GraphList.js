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

    construct: function (url) {

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
		this._url = url;
   		qx.event.message.Bus.subscribe('sp.menu.folder',this._load_graphs,this);
    },

	members: {
		_load_graphs: function(m){
			var files = m.getData()
			this.removeAll();
			for(var i=0;i<files.length;i++){
                var shadow = new Smokeping.GraphShadow();
                shadow.set({
                    width: 150,
                    height: 75,
                    start: Math.round((new Date()).getTime()/1000)-(3600*24*3),
                    end: Math.round((new Date()).getTime()/1000),
                    top: 1000000,
                    bottom: 0,
                    cgi: this._url + 'grapher.cgi',
                    data: files[i]
                });
   			   	var image = new Smokeping.ui.Graph(shadow);
				this.add(image);
			}
		}
	}
	

});
 
 
