/* ************************************************************************

#module(Smokeping)
#resource(Smokeping.image:image)
#embed(Smokeping.image/*)

************************************************************************ */

qx.Class.define('Smokeping.Application', 
{
    extend: qx.application.Gui,
       
    members: 
    {           
        main: function()
        {
            var self=this;
            this.base(arguments);

	        qx.io.Alias.getInstance().add(
    	       'SP', qx.core.Setting.get('Smokeping.resourceUri')
        	);

  			// if we run with a file:// url make sure 
			// the app finds the smokeping service (smokeping.cgi)
			Smokeping.Server.getInstance().setLocalUrl(
				'http://localhost/~oetiker/smq/'
			);

            var base_layout = new qx.ui.layout.VerticalBoxLayout();
            with(base_layout){
                setPadding(8);
                setLocation(0,0);
                setWidth('100%');
                setHeight('100%');
                setSpacing(10);
            };            
            base_layout.addToDocument();
			var title = new qx.ui.basic.Atom(this.tr('Smokeping Viewer'));
			with(title){
            	setTextColor('#b0b0b0');
            	setFont(qx.ui.core.Font.fromString('16px bold sans-serif'));
			}
			base_layout.add(title);

		    var splitpane = new qx.ui.splitpane.HorizontalSplitPane(200, '1*');
		    splitpane.setEdge(0);
			splitpane.setHeight('1*');
		    splitpane.setShowKnob(true);
  		    base_layout.add(splitpane);

 		    var tree = new Smokeping.ui.TargetTree();
	        splitpane.addLeft(tree);

			var graphlist = new Smokeping.ui.GraphList();
			splitpane.addRight(graphlist);
 

        },
        
        close : function(e)
        {
            this.base(arguments);
            // return "Smokeping Web UI: "
            //      + "Do you really want to close the application?";
        },
        
			
		terminate : function(e) {
			this.base(arguments);
		}

        /********************************************************************
         * Functional Block Methods
         ********************************************************************/

    },
		



    /*
    *****************************************************************************
    SETTINGS
    *****************************************************************************
    */

    settings : {
			'Smokeping.resourceUri' : './resource'
	}
});
 
