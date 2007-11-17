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
            setOverflow('scrollY');
            setBackgroundColor('white');
		    setBorder(new qx.ui.core.Border(1,'solid','#a0a0a0'));
            setWidth('100%');
            setHeight('100%');
            setVerticalSpacing(10);
            setHorizontalSpacing(10);
			setPadding(10);
        };
		this._url = url;
   		qx.event.message.Bus.subscribe('sp.menu.folder',this._load_graphs,this);
    },

	members: {
		_load_graphs: function(m){
			var files = m.getData()
			this.removeAll();
			for(var i=0;i<files.length;i++){
   			   	var button = new Smokeping.ui.Graph(this._url + 'grapher.cgi?g=' + files[i]);
				this.add(button);
			}
		}
	}
	

});
 
 
