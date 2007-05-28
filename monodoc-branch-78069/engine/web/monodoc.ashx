<%@ WebHandler Language="c#" class="Mono.Website.Handlers.MonodocHandler" %>
<%@ Assembly name="monodoc" %>

#define MONODOC_PTREE

//
// Mono.Web.Handlers.MonodocHandler.  
//
// Authors:
//     Ben Maurer (bmaurer@users.sourceforge.net)
//     Miguel de Icaza (miguel@novell.com)
//
// (C) 2003 Ben Maurer
// (C) 2006 Novell, Inc.
//

using System;
using System.Collections;
using System.IO;
using System.Text;
using System.Web;
using System.Web.UI;
using System.Xml;
using System.Xml.Xsl;
using Monodoc;
using System.Text.RegularExpressions;

namespace Mono.Website.Handlers
{
	public class MonodocHandler : IHttpHandler
	{
		static RootTree help_tree;
		
		static MonodocHandler ()
		{
			help_tree = RootTree.LoadTree ();
		}
		
		void IHttpHandler.ProcessRequest (HttpContext context)
		{
			string s;

			s = (string) context.Request.Params["tlink"];
			if (s != null){
				HandleTreeLink (context, s);
				return;
			}
			
			s = (string) context.Request.Params["link"];
			if (s != null){
				HandleMonodocUrl (context, s);
				return;
			}

			s = (string) context.Request.Params["tree"];
			if (s != null){
				if (s == "boot")
					HandleBoot (context);
				else {
					HandleTree (context, s);
				}
				return;
			}
			context.Response.Write ("<html><body>Unknown request</body></html>");
			context.Response.ContentType = "text/html";
		}
		
		void HandleTree (HttpContext context, string tree)
		{
		    context.Response.ContentType = "text/xml";
		    //Console.WriteLine ("Tree request: " + tree);
		    try {
			//
			// Walk the url, found what we are supposed to render.
			//
			string [] nodes = tree.Split (new char [] {'@'});
			Node current_node = help_tree;
			for (int i = 0; i < nodes.Length; i++){
				try {
				current_node = (Node)current_node.Nodes [int.Parse (nodes [i])];
				} catch (Exception e){
					Console.WriteLine ("Failure with: {0} {i}", tree, i);
				}
			}

			XmlTextWriter w = new XmlTextWriter (context.Response.Output);

			w.WriteStartElement ("tree");

			for (int i = 0; i < current_node.Nodes.Count; i++) {
				Node n = (Node)current_node.Nodes [i];

				w.WriteStartElement ("tree");
				w.WriteAttributeString ("text", n.Caption);

				if (n.tree != null && n.tree.HelpSource != null)
					w.WriteAttributeString ("action", n.tree.HelpSource.SourceID + "@" + HttpUtility.UrlEncode (n.URL));

				if (n.Nodes != null){
					w.WriteAttributeString ("src", tree + "@" + i);
				}
				w.WriteEndElement ();
			}
			w.WriteEndElement ();
	           } catch (Exception e) {
			Console.WriteLine (e);
		   }
		   //Console.WriteLine ("Tree request satisfied");
		}
		
		void CheckLastModified (HttpContext context)
		{
			string strHeader = context.Request.Headers ["If-Modified-Since"];
			DateTime lastHelpSourceTime = help_tree.LastHelpSourceTime;
			try {
				if (strHeader != null && lastHelpSourceTime != DateTime.MinValue) {
					DateTime dtIfModifiedSince = DateTime.ParseExact (strHeader, "r", null);
					DateTime ftime = lastHelpSourceTime.ToUniversalTime ();
					if (ftime <= dtIfModifiedSince) {
						context.Response.StatusCode = 304;
						return;
					}
				}
			} catch { } 

			if (lastHelpSourceTime != DateTime.MinValue) {
				DateTime lastWT = lastHelpSourceTime.ToUniversalTime ();
				context.Response.AddHeader ("Last-Modified", lastWT.ToString ("r"));
			}

		}

		void HandleMonodocUrl (HttpContext context, string link)
		{
			if (link.StartsWith ("source-id:") &&
				(link.EndsWith (".gif") || link.EndsWith (".jpeg") ||
				 link.EndsWith (".jpg")  || link.EndsWith(".png"))){
				switch (link.Substring (link.LastIndexOf ('.') + 1))
				{
				case "gif":
					context.Response.ContentType = "image/gif";
					break;
				case "jpeg":
				case "jpg":
					context.Response.ContentType = "image/jpeg";
					break;
				case "png":
					context.Response.ContentType = "image/png";
					break;
				default:
					throw new Exception ("Internal error");
				}
				
				Stream s = help_tree.GetImage (link);
				
				if (s == null)
					throw new HttpException (404, "File not found");
				
				CheckLastModified (context);
				if (context.Response.StatusCode == 304)
					return;

				Copy (s, context.Response.OutputStream);
				return;
			}

			if (help_tree == null)
				return;
			Node n;
			string content = help_tree.RenderUrl (link, out n);
			CheckLastModified (context);
			if (context.Response.StatusCode == 304)
				return;

			PrintDocs (content, context);
		}
		
		void HandleTreeLink (HttpContext context, string link)
		{
			string [] lnk = link.Split (new char [] {'@'});
			
			if (lnk.Length == 1) {
				HandleMonodocUrl (context, link);
				return;
			}
				
			int hsId = int.Parse (lnk [0]);
			
			Node n;
			string content = help_tree.GetHelpSourceFromId (hsId).GetText (lnk [1], out n);
			if (content == null)
				content = help_tree.RenderUrl (lnk [1], out n);
			PrintDocs (content, context);
			
		}

		void Copy (Stream input, Stream output)
		{
			const int BUFFER_SIZE=8192; // 8k buf
			byte [] buffer = new byte [BUFFER_SIZE];

			int len;
			while ( (len = input.Read (buffer, 0, BUFFER_SIZE)) > 0)
				output.Write (buffer, 0, len);

			output.Flush();
		}

		string requestPath;
		void PrintDocs (string content, HttpContext ctx)
		{
			ctx.Response.Write (@"
<html>
<head>
		<link type='text/css' rel='stylesheet' href='common.css' media='all' title='Default style' />
<script>
<!--
function login (rurl)
{
	document.location.href = 'login.aspx?ReturnUrl=' + rurl;
}

function load ()
{
	// If topic loaded in a window by itself, load index.aspx with the same set of params.
	if (top.location == document.location)
	{
		top.location.href = 'index.aspx'+document.location.search;
	}
	parent.Header.document.getElementById ('pageLink').href = parent.content.window.location;
	objs = document.getElementsByTagName('img');
	for (i = 0; i < objs.length; i++)
	{
		e = objs [i];
		if (e.src == null) continue;
		
		objs[i].src = makeLink (objs[i].src);
	}
}

function makeLink (link)
{
	if (link == '') return '';
	if (link.charAt(0) == '#') return link;
	
	protocol = link.substring (0, link.indexOf (':'));

	switch (protocol)
		{
		case 'http':
		case 'ftp':
		case 'mailto':
			return link;
			
		default:
			if(document.all) {
				return '" + ctx.Request.Path + @"?link=' + link.replace(/\+/g, '%2B').replace(/file:\/\/\//, '');
			}
			return '" + ctx.Request.Path + @"?link=' + link.replace(/\+/g, '%2B');
		}
}
-->
	</script>
		<title>Mono Documentation</title>
		</head>
		<body onLoad='load()'>
		");
			// Set up object variable, as it's required by the MakeLink delegate
			requestPath=ctx.Request.Path;
			string output;

			if (content == null)
				output = "No documentation available on this topic";
			else {
				output = MakeLinks(content);
			}
			ctx.Response.Write (output);
			ctx.Response.Write (@"</body></html>");
		}


		string MakeLinks(string content)
		{
			MatchEvaluator linkUpdater=new MatchEvaluator(MakeLink);
			if(content.Trim().Length<1|| content==null)
				return content;
			try
			{
				string updatedContents=Regex.Replace(content,"(<a[^>]*href=['\"])([^'\"]+)(['\"][^>]*)(>)", linkUpdater);
				return(updatedContents);
			}
			catch(Exception e)
			{
				return "LADEDA" + content+"!<!--Exception:"+e.Message+"-->";
			}
		}
		
		// Delegate to be called from MakeLinks for fixing <a> tag
		string MakeLink (Match theMatch)
		{
			string updated_link = null;

			// Return the link without change if it of the form
			//	$protocol://... or #...
			string link = theMatch.Groups[2].ToString();
			if (Regex.Match(link, @"^\w+:\/\/").Success || Regex.Match(link, "^#").Success)
				updated_link = theMatch.Groups[0].ToString();
			else if (link.StartsWith ("edit:")){
				link = link.Substring (5);
 				updated_link = String.Format("{0}/edit.aspx?link={2}{3} target=\"content\"{4}",
 					theMatch.Groups[1].ToString(),
 					requestPath, 
 					HttpUtility.UrlEncode (link.Replace ("file://","")),
 						theMatch.Groups[3].ToString(),
 						theMatch.Groups[4].ToString());
			
			} else {
				updated_link = String.Format ("{0}{1}?link={2}{3} target=\"content\"{4}",
					theMatch.Groups[1].ToString(),
                                        requestPath,
                                        HttpUtility.UrlEncode (link.Replace ("file://","")),
						theMatch.Groups[3].ToString(),
                                                theMatch.Groups[4].ToString());

			}
			return updated_link;
		}
		
		bool IHttpHandler.IsReusable
		{
			get {
				return true;
			}
		}

		void HandleBoot (HttpContext context)
				{
			context.Response.Write (@"
<html>
	<head>
		<link type='text/css' rel='stylesheet' href='ptree/tree.css'/>
		<link type='text/css' rel='stylesheet' href='sidebar.css'/>
		<script src='xtree/xmlextras.js'></script>
		<script src='ptree/tree.js'></script>
		<script src='sidebar.js'></script>
		<script>
		var tree = new PTree ();
		function onBodyLoad ()
		{
			tree.strTargetDefault = 'content';
			tree.strSrcBase = 'monodoc.ashx?tree=';
			tree.strActionBase = 'monodoc.ashx?tlink=';
			tree.strImagesBase = 'xtree/images/msdn2/';
			tree.strImageExt = '.gif';
			var content = document.getElementById ('contentList');
			var root = tree.CreateItem (null, 'Mono Documentation', 'intro.html', '', true);
			content.appendChild (root);
		");

		for (int i = 0; i < help_tree.Nodes.Count; i++){
			Node n = (Node)help_tree.Nodes [i];
			context.Response.Write (
				"tree.CreateItem (root, '" + n.Caption + "', '" +
				n.URL + "', ");
	
			if (n.Nodes.Count != 0)
				context.Response.Write ("'" + i + "'");
			else	
				context.Response.Write ("null");
	
			if (i == help_tree.Nodes.Count-1)
				context.Response.Write (", true");

			context.Response.Write (@");
			");
		}
		context.Response.Write (@"
		}</script>
	</head>
	<body onLoad='javascript:onBodyLoad();' onkeydown='javascript:return tree.onKeyDown (event);'>
	  <div id='tabs'>
	    <ul>
	      <li id='contentsTab' class='selected'><a href='javascript:ShowContents();'>Contents</a></li>
	      <li id='indexTab' style='display:none;'><a href='javascript:ShowIndex();'>Index</a></li>
	    </ul>
	  </div>
	  <div id='contents' class='activeTab'>
	    <div id='contentList'>
	    </div>
	  </div>
	  <div id='index' class='tab'>
	    <p>
	    <label for='indexInput'>Lookup:</label> <input type='text' id='indexInput'/>
	    <img alt='Spinner-blue' id='search_spinner' src='images/searching.gif' style='display:none;' align='middle' />
	    <p id='errorText'></p>
	    <ul id='indexList'></ul>
	  </div>
	</body>
</html>
");
		}
	}
}
