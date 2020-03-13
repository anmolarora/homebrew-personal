class Qt5Webkit < Formula
  # Some notes:
  # 1. I copy this formula from https://github.com/OSGeo/homebrew-osgeo4mac/blob/master/Formula/qt5-webkit.rb,
  #    and remove unnecessary libraries dependency.
  # 2. I use branch name as "version" instead of qt "version.
  # 3. I remove bottle part, you have to compile this forumla from source by yourself.
  desc "Classes for a WebKit2 based implementation and a new QML API"
  homepage "https://www.qt.io/developers"
  url "https://github.com/qt/qtwebkit.git",
    :branch => "5.212",
    :commit => "eb6c5179e8650f66b304a656409a1e5e5efec956"
  version "5.212"

  # if it is changed this should be applied in CMAKE_INSTALL_PREFIX (see patch)
  # in the same way for "version"

  # from the developer: "https://github.com/annulen/webkit.git"
  head "https://github.com/qt/qtwebkit.git"

  # fix installation permissions
  # /Tools/qmake/projects/run_cmake.pro
  patch do
    url "https://raw.githubusercontent.com/anmolarora/homebrew-personal/master/Formula/qt5-webkit.diff"
    sha256 "96ccb8b922ae79bc7a3cd8bfe51a2b12f05f89598a839eafb81d24f27b527fa9"
  end

  keg_only "because Qt5 is keg-only"

  depends_on "cmake" => :build
  depends_on :xcode => :build
  depends_on "libjpeg"
  depends_on "libpng"
  depends_on "qt"

  def install
    # on Mavericks we want to target libc++, this requires a macx-clang flag
    spec = (ENV.compiler == :clang && MacOS.version >= :mavericks) ? "macx-clang" : "macx-g++"
    args = %W[-config release -spec #{spec}]

    mkdir "build" do
      system "#{Formula["qt"].opt_bin}/qmake", "../WebKit.pro", *args
      system "make"
      system "make", "install"
    end

    # rename the .so files
    mv "#{lib}/qml/QtWebKit/libqmlwebkitplugin.so", "#{lib}/qml/QtWebKit/libqmlwebkitplugin.dylib"
    mv "#{lib}/qml/QtWebKit/experimental/libqmlwebkitexperimentalplugin.so", "#{lib}/qml/QtWebKit/experimental/libqmlwebkitexperimentalplugin.dylib"

    ln_s "#{lib}/qml", "#{prefix}/qml"
    ln_s "#{lib}/libexec", "#{prefix}/libexec"

    # some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink Dir["#{lib}/*.framework"]

    # the pkg-config files installed suggest that headers can be found in the
    # `include` directory. Make this so by creating symlinks from `include` to
    # the Frameworks' Headers folders
    Pathname.glob("#{lib}/*.framework/Headers") do |path|
      include.install_symlink path => path.parent.basename(".framework")
    end

    # for some reason it is not generating the .pc files, that's why they are created
    # although these are not necessary
    mkdir "#{lib}/pkgconfig" do
      # create Qt5WebKit.pc
      File.open("#{lib}/pkgconfig/Qt5WebKit.pc", "w") { |file|
        file << "Name: Qt5WebKit\n"
        file << "Description: Qt WebKit module\n"
        file << "Version: #{version}\n"
        # file << "Libs: -F#{lib} -framework QtWebKit"
        file << "Libs: -L#{lib} -lQt5WebKit\n"
        # file << "Cflags: -DQT_WEBKIT_LIB -I#{include}/QtWebKit\n"
        file << "Cflags: -I#{include}/QtWebKit\n"
        file << "Requires: Qt5Core Qt5Gui Qt5Network"
      }
      # create QtWebKitWidgets.pc
      File.open("#{lib}/pkgconfig/Qt5WebKitWidgets.pc", "w") { |file|
        file << "Name: Qt5WebKitWidgets\n"
        file << "Description: Qt WebKitWidgets module\n"
        file << "Version: #{version}\n"
        # file << "Libs: -F#{lib} -framework QtWebKitWidgets"
        file << "Libs: -L#{lib} -lQt5WebKitWidgets\n"
        # file << "Cflags: -DQT_WEBKITWIDGETS_LIB -I#{include}/QtWebKitWidgets\n"
        file << "Cflags: -I#{include}/QtWebKitWidgets\n"
        file << "Requires:"
      }
    end

    # fix rpath values
    MachO::Tools.change_install_name("#{lib}/QtWebKitWidgets.framework/Versions/5/QtWebKitWidgets",
                                    "@rpath/QtWebKit.framework/Versions/5/QtWebKit",
                                    "#{lib}/QtWebKit.framework/Versions/5/QtWebKit")
    MachO::Tools.change_install_name("#{prefix}/qml/QtWebKit/libqmlwebkitplugin.dylib",
                                    "@rpath/QtWebKit.framework/Versions/5/QtWebKit",
                                    "#{lib}/QtWebKit.framework/Versions/5/QtWebKit")
    MachO::Tools.change_install_name("#{prefix}/qml/QtWebKit/experimental/libqmlwebkitexperimentalplugin.dylib",
                                    "@rpath/QtWebKit.framework/Versions/5/QtWebKit",
                                    "#{lib}/QtWebKit.framework/Versions/5/QtWebKit")
    MachO::Tools.change_install_name("#{libexec}/QtWebProcess",
                                     "@rpath/QtWebKitWidgets.framework/Versions/5/QtWebKitWidgets",
                                     "#{lib}/QtWebKitWidgets.framework/Versions/5/QtWebKitWidgets")
    MachO::Tools.change_install_name("#{libexec}/QtWebProcess",
                                    "@rpath/QtWebKit.framework/Versions/5/QtWebKit",
                                    "#{lib}/QtWebKit.framework/Versions/5/QtWebKit")
  end

  test do
    (testpath/"hello.pro").write <<~EOS
      QT        += core webkitwidgets
      QT        -= gui
      TARGET     = hello
      CONFIG    += console
      CONFIG    -= app_bundle
      TEMPLATE   = app
      HEADERS    = client.h
      SOURCES   += client.cpp main.cpp
      include(#{prefix}/mkspecs/modules/qt_lib_webkit.pri)
      include(#{prefix}/mkspecs/modules/qt_lib_webkitwidgets.pri)
    EOS

    (testpath/"client.h").write <<~EOS
    #ifndef CLIENT_H
    #define CLIENT_H
    #include <QWebPage>
    #include <QString>

    class Client : public QObject
    {
      Q_OBJECT

    public:
      Client(const QString &url, QObject *parent = 0);

    private Q_SLOTS:
      void loadUrl();
      void output(bool ok);

    private:
      QWebPage page;
      QString url;

    };
    #endif // CLIENT_H
    EOS

    (testpath/"client.cpp").write <<~EOS
    #include "client.h"
    #include <QCoreApplication>
    #include <QDebug>
    #include <QWebFrame>
    #include <QUrl>

    Client::Client(const QString &myurl, QObject *parent)
      : QObject(parent)
      , url(myurl)
    {
    }

    void Client::loadUrl()
    {
      page.mainFrame()->load(QUrl(url));
      connect(&page, SIGNAL(loadFinished(bool)), this, SLOT(output(bool)));
    }

    void Client::output(bool ok)
    {
      if (ok){
        qDebug() << "Page title: " << page.mainFrame()->title();
        QCoreApplication::exit(0);
      } else {
        qDebug() << "Error loading " << url;
        QCoreApplication::exit(1);
      }
    }
    EOS

    (testpath/"main.cpp").write <<~EOS
      #include <QApplication>
      #include <QDebug>
      #include <QTimer>
      #include <QWebView>
      #include "client.h"

      int main(int argc, char *argv[])
      {
        QApplication app(argc, argv);
        Client c("file://#{testpath}/test.html", app.instance());
        qDebug() << "Running application";
        QTimer::singleShot(1000, &c, SLOT(loadUrl()));
        return app.exec();
      }
    EOS

    (testpath/"test.html").write <<~EOS
      <!DOCTYPE html>
      <html lang="en">
      <head><meta charset="utf-8" /><title>My title</title></head>
      <body>Body content</body>
      </html>
    EOS

    cd testpath do
      system Formula["qt5"].bin/"qmake", "hello.pro"
      system "make"
      assert_predicate testpath/"client.o", :exist?
      assert_predicate testpath/"moc_client.o", :exist?
      assert_predicate testpath/"main.o", :exist?
      assert_predicate testpath/"hello", :exist?

      # test that we can actually serve the page
      pid = fork do
        exec testpath/"hello"
      end
      sleep 2
      begin
        assert_match "<html><body><h1>It works!</h1></body></html>\n", shell_output("curl http://localhost:80")
      ensure
        Process.kill("SIGINT", pid)
        Process.wait(pid)
      end
    end
  end
end
