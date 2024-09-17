/*
 * Copyright 2020-present HiveMQ GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.hivemq.extensions.x509extension;

import com.hivemq.extension.sdk.api.auth.SimpleAuthenticator;
import com.hivemq.extension.sdk.api.auth.parameter.SimpleAuthInput;
import com.hivemq.extension.sdk.api.auth.parameter.SimpleAuthOutput;
import com.hivemq.extension.sdk.api.client.parameter.ClientTlsInformation;
import org.jetbrains.annotations.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.security.cert.X509Certificate;


public class X509Authenticator implements SimpleAuthenticator {
    private static final @com.hivemq.extension.sdk.api.annotations.NotNull Logger log = LoggerFactory.getLogger(X509Authenticator.class);

    @Override
    public void onConnect(final @NotNull SimpleAuthInput input, final @NotNull SimpleAuthOutput output) {
        final ClientTlsInformation tlsInformation = input.getConnectionInformation().getClientTlsInformation()
                .get();
        final X509Certificate certificate = tlsInformation.getClientCertificate().get();

        if ("alwaystrustme".equals(certificate.getIssuerDN().getName())) {
            log.info("Issuer was alwaystrustme, client is allowed to use all topics with all permissions");
            output.authenticateSuccessfully();
        } else {
            log.info("Issuer is: " + certificate.getIssuerDN().getName());
        }

        output.nextExtensionOrDefault();
    }
}
