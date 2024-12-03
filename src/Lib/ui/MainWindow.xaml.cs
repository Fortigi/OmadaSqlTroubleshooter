using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;


namespace OmadaSqlTroubleshooter
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            this.Loaded += Window_Loaded;
        }


        public async void Window_Loaded(object sender, RoutedEventArgs e)
        {
            this.webView21.Source =
            new Uri(System.IO.Path.Combine(
            System.AppDomain.CurrentDomain.BaseDirectory,
            @"Monaco\index.html"));
        }
    }
}