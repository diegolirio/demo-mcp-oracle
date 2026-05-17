package com.example.demo_mcp_oracle;

import org.springframework.boot.SpringApplication;

public class TestDemoMcpOracleApplication {

	public static void main(String[] args) {
		SpringApplication.from(DemoMcpOracleApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
