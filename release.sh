VERSION=`grep -E '<version>([0-9]+\.[0-9]+\.[0-9]+)</version>' pom.xml | sed 's/[\t \n]*<version>\(.*\)<\/version>[\t \n]*/\1/'`
ARTIFACT="$PWD/pkg/killbill-paypal-express-$VERSION.tar.gz"
echo "Pushing $ARTIFACT to Maven Central"
mvn gpg:sign-and-deploy-file \
    -DgroupId=com.ning.killbill.ruby \
    -DartifactId=paypal-express-plugin \
    -Dversion=$VERSION \
    -Dpackaging=tar.gz \
    -DrepositoryId=ossrh-releases \
    -Durl=https://oss.sonatype.org/service/local/staging/deploy/maven2/ \
    -Dfile=$ARTIFACT
