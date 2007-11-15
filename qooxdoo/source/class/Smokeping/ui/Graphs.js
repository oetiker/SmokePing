/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping graph overview
 */

qx.Class.define('Smokeping.ui.Graphs', 
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
			base(arguments,'root node');
            setOverflow('scrollY');
            setBackgroundColor('white');
            setBorder('inset');
            setWidth('100%');
            setHeight('100%');
            setVerticalSpacing(10);
            setHorizontalSpacing(10);
        };
        for(var i=0;i<2000;i++){
            var button = new qx.ui.basic.Atom(i.toString());
            this.add(button);
        }
    },

    /*
    *****************************************************************************
     Statics
    *****************************************************************************
    */

    statics :
    {

		/*
        ---------------------------------------------------------------------------
        CORE METHODS
        ---------------------------------------------------------------------------
        */

        /**
         * Create the tree based on input from the Server
         *
         * @type member
		 *
         * @param {void}
         *
		 * @return BaseUrl {Strings}
		 */


        __fill_folder: function(node,data){
			// in data[0] we have the id of the folder
			var folder = new qx.ui.tree.TreeFolder(data[1]);
			node.add(folder);
			var length = data.length;
			for (var i=2;i<length;i++){
				if(qx.util.Validation.isValidArray(data[i])){
					Smokeping.ui.TargetTree.__fill_folder(folder,data[i]);
				} else {
					i++; // skip the node id for now
					var file = new qx.ui.tree.TreeFile(data[i]);		
					folder.add(file);
				}
			}			
		}

    }
});
 
 
