//
// TestDocumentBufferArchiver.cs: Test unit for DocumentBufferArchiver class.
//
// Author:
//   Hector E. Gomez M (hectorgm@ciencias.unam.mx)
//
// (C) 2007 Hector E. Gomez M

using Gtk;
using System;
using System.IO;
using NUnit.Framework;
using Monodoc.Editor.Utils;

namespace Monodoc.Editor.Gui {
[TestFixture()]
public class TestDocumentBufferArchiver {
	
	private string pathTest;
	private string [] files;
	
	[SetUp()]
	public void Initialize ()
	{
		string filePath = Test.PathOfTestFiles ();
		pathTest = Path.Combine (filePath, "Examples");
		files = Directory.GetFiles (pathTest, "*.xml");
		
		Application.Init ();
	}
	
	[TearDown()]
	public void Dispose ()
	{
		Application.Quit ();
	}
	
	[Test()]
	public void Serialize()
	{
		string originalText, newText, filename;
		
		foreach (string file in files) {
			DocumentEditor editor = new DocumentEditor ();
			TextBuffer buffer = editor.Buffer;
			
			MonoDocument document = new MonoDocument (file);
			filename = Path.GetFileName (file);
			originalText = document.Text;
			
			DocumentBufferArchiver.Deserialize (buffer, originalText);
			newText = DocumentBufferArchiver.Serialize (buffer);
			
			Assert.AreEqual (originalText, newText, "SR:" + filename);
		}
	}
	
	[Test()]
	public void SerializePerformance ()
	{
		string originalText, filename;
		
		foreach (string file in files) {
			DocumentEditor editor = new DocumentEditor ();
			TextBuffer buffer = editor.Buffer;
			
			MonoDocument document = new MonoDocument (file);
			filename = Path.GetFileName (file);
			originalText = document.Text;
			
			DocumentBufferArchiver.Deserialize (buffer, originalText);
			DateTime startTime = DateTime.Now;
			DocumentBufferArchiver.Serialize (buffer);
			DateTime stopTime = DateTime.Now;
			TimeSpan duration = stopTime - startTime;
			
			Assert.Less (duration.TotalMilliseconds, 500, "SP:" + filename);
		}
	}
	
	[Test()]
	public void DeserializePerformance ()
	{
		string originalText, filename;
		
		foreach (string file in files) {
			DocumentEditor editor = new DocumentEditor ();
			TextBuffer buffer = editor.Buffer;
			
			MonoDocument document = new MonoDocument (file);
			filename = Path.GetFileName (file);
			originalText = document.Text;
			
			DateTime startTime = DateTime.Now;
			DocumentBufferArchiver.Deserialize (buffer, originalText);
			DateTime stopTime = DateTime.Now;
			TimeSpan duration = stopTime - startTime;
			
			Assert.Less (duration.TotalMilliseconds, 100, "SP:" + filename);
		}
	}
}
}