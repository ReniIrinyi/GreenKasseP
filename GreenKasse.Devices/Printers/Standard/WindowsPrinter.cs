using System;
using System.Drawing;
using System.Drawing.Printing;

public static class WindowsPrinter
{
    public static void PrintText(string text)
    {
        if (text == null) text = string.Empty;

        using var doc = new PrintDocument(); // default printer
        doc.DocumentName = "Bon (fallback)";
        doc.PrintPage += (s, e) =>
        {
            using var font = new Font("Segoe UI", 10);
            var bounds = e.MarginBounds;
            e.Graphics.DrawString(text, font, Brushes.Black, bounds);
            e.HasMorePages = false;
        };
        doc.Print();
    }
}