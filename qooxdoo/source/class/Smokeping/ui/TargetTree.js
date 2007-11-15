/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping target tree
 */

qx.Class.define('Smokeping.ui.TargetTree', 
{
    extend: qx.ui.tree.Tree,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param root_node  {String}   Name of the root node
     *                              where will we find our RPC server.
     *
     * @param rpc        {rpcObject}  An rpc object providing access to the Smokeping service
     */

    construct: function (rpc) {

        with(this){
			base(arguments,'root node');
            setBackgroundColor('white');
            setBorder('inset');
//			setOverflow('scrollY');
            setWidth('100%'); 
            setHeight('100%');
            setPadding(5);
			setHideNode(true);
        };

        var self = this;

		var fill_tree = function(data,exc,id){
			if (exc == null){
				var nodes = data.length;
				for(var i=0;i<nodes;i++){
					Smokeping.ui.TargetTree.__fill_folder(self,data[i]);		
				}
			}
			else {
				alert(exc);
			}				
        };

        rpc.callAsync(fill_tree,'get_tree');		
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
			folder.setUserData('id',data[0]);
			node.add(folder);
			var length = data.length;
			for (var i=2;i<length;i++){
				if(qx.util.Validation.isValidArray(data[i])){
					Smokeping.ui.TargetTree.__fill_folder(folder,data[i]);
				} else {
					i++; // skip the node id for now
					var file = new qx.ui.tree.TreeFile(data[i]);		
					file.setUserData('id',data[i-1]);
					folder.add(file);
				}
			}			
		}

    }
});
 
 
