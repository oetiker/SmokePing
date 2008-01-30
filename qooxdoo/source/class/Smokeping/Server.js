/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * A smokeping specific rpc call which works 
 */

qx.Class.define('Smokeping.Server', 
{
    extend: qx.io.remote.Rpc,        
	type:   "singleton",

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param local_url {String}    When running the application in file:// mode.
     *                              where will we find our RPC server.
     */
    construct: function (local_url) {

        with(this){
			base(arguments);
            setTimeout(7000000);
            setUrl('smokeping.cgi');
            setServiceName('Smokeping');
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

        getBaseUrl: function(){
            return  this.__base_url;
        },

		setLocalUrl: function(local_url){
			if ( document.location.host === '' ) {
				with(this){
	            	setUrl(local_url+'smokeping.cgi');
    	        	setCrossDomain(true);
				}
	        }
		}

    }
});
 
