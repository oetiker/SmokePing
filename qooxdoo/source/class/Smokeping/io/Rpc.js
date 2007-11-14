/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * A smokeping specific rpc call which works 
 */

qx.Class.define('Smokeping.io.Rpc', 
{
    extend: qx.io.remote.Rpc,        

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
            setUrl('jsonrpc.cgi');
            setServiceName('Smokeping');
        }

        var our_href = new String(document.location.href);
        var last_slash = our_href.lastIndexOf("/");
        this.__base_url = our_href.substring(0,last_slash+1);   

		// look for services on the localhost if we access the
        // application locally

        if ( document.location.host === '' ) {
			with(this){
	            __base_url = local_url;
            	setUrl(__base_url + 'jsonrpc.cgi');
            	setCrossDomain(true);
			}
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
        }
    }
});
 
