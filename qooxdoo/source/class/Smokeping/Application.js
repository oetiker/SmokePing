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

			// this will provide access to the server side of this app
			var rpc = new Smokeping.io.Rpc('http://localhost/~oetiker/smq');
            
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
		    splitpane.setEdge(1);
			splitpane.setHeight('1*');
		    splitpane.setShowKnob(true);
  		    prime.add(splitpane);

 		    var tree = new Smokeping.ui.TargetTree(rpc,this.tr("Root Node"));
	        splitpane.addLeft(tree);

			var graphs = new qx.ui.layout.VerticalBoxLayout();
			with(graphs){
				setBackgroundColor('white');
				setBorder('inset');
				setWidth('100%');
				setHeight('100%');
			};

			splitpane.addRight(graphs);


        },
        
        close : function(e)
        {
            this.base(arguments);
            // return "Smokeping Web UI: "
            //      + "Do you really want to close the application?";
        },
        
			
		terminate : function(e) {
			this.base(arguments);
		},

        /********************************************************************
         * Functional Block Methods
         ********************************************************************/

        /**
        * Get the base url of this page
        *
        * @return {String} the base url of the page
        */

        __getBaseUrl: function() {
            var our_href = new String(document.location.href);
            var last_slash = our_href.lastIndexOf("/");
            return our_href.substring(0,last_slash+1);   
        }
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
 
