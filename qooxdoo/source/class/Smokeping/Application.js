/* ************************************************************************

#module(Smokeping)
#resource(Smokeping.image:image)
#embed(Smokeping.image/*)

************************************************************************ */

qx.Class.define(
    'Smokeping.Application', {
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

  			// this will provide access to the server side of this app
			var rpc = new Smokeping.io.Rpc('http://localhost/~oetiker/smq/');
            
			var base_url = rpc.getBaseUrl();

            var prime = new qx.ui.layout.VerticalBoxLayout();
            with(prime){
                setPadding(8);
                setLocation(0,0);
                setWidth('100%');
                setHeight('100%');
                setSpacing(10);
            };            
            prime.addToDocument();
			var title = new qx.ui.basic.Atom(this.tr('Smokeping Viewer'));
			with(title){
            	setTextColor('#b0b0b0');
            	setFont(qx.ui.core.Font.fromString('16px bold sans-serif'));
			}
			prime.add(title);

		    var splitpane = new qx.ui.splitpane.HorizontalSplitPane('1*', '3*');
		    splitpane.setEdge(0);
			splitpane.setHeight('1*');
		    splitpane.setShowKnob(true);
  		    prime.add(splitpane);

 		    var tree = new Smokeping.ui.TargetTree(rpc);
	        splitpane.addLeft(tree);

			var graphlist = new Smokeping.ui.GraphList(rpc.getBaseUrl());
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
	}
);
 
