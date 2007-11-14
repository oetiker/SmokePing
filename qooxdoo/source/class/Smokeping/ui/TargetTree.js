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

    construct: function (rpc,root_node) {

        with(this){
			base(arguments,root_node);
            setBackgroundColor('white');
            setBorder('inset');
            setWidth('100%'); 
            setHeight('100%');
            setPadding(5);
        }

		return this;
    },

    /*
    *****************************************************************************
     MEMBERS
    *****************************************************************************
    */

    members :
    {

		/*
        ---------------------------------------------------------------------------
        CORE METHODS
        ---------------------------------------------------------------------------
        */

        /**
         * Tell about the BaseUrl we found.
         *
         * @type member
		 *
         * @param {void}
         *
		 * @return BaseUrl {Strings}
		 */

//        getBaseUrl: function(){
//            return  this.__base_url;
//        }
    }
});
 
 
