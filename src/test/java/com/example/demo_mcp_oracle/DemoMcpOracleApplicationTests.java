package com.example.demo_mcp_oracle;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@Import(TestcontainersConfiguration.class)
@SpringBootTest
class DemoMcpOracleApplicationTests {

	@Test
	void contextLoads() {
	}

}
